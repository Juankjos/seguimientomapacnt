<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

// INPUT (JSON o FORM)
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// AUTH
$user = require_auth($pdo, is_array($in) ? $in : []);
$role = (string)($user['role'] ?? 'reportero');
$userId = (int)($user['id'] ?? 0);

if (!in_array($role, ['admin', 'reportero'], true)) {
  http_response_code(403);
  echo json_encode(['success' => false, 'message' => 'Rol inválido']);
  exit;
}

$noticiaId = isset($in['noticia_id']) ? (int)$in['noticia_id'] : 0;
if ($noticiaId <= 0) {
  echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
  exit;
}

// Target reportero:
// - reportero: SIEMPRE se asigna a sí mismo
// - admin: puede asignar a cualquiera
$reporteroId = 0;

if ($role === 'admin') {
  $reporteroId = isset($in['reportero_id']) ? (int)$in['reportero_id'] : 0;
  if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
  }
} else {
  $reporteroId = $userId;
}

try {
  $pdo->beginTransaction();

  // Lock noticia para evitar que 2 la tomen al mismo tiempo
  $stmtN = $pdo->prepare("
    SELECT id, noticia, reportero_id, fecha_cita, IFNULL(limite_tiempo_minutos, 60) AS limite
    FROM noticias
    WHERE id = ?
    LIMIT 1
    FOR UPDATE
  ");
  $stmtN->execute([$noticiaId]);
  $n = $stmtN->fetch(PDO::FETCH_ASSOC);

  if (!$n) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'La noticia no existe']);
    exit;
  }

  if (!empty($n['reportero_id'])) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'La noticia ya fue tomada por otro reportero']);
    exit;
  }

  // Lock reportero
  $stmtR = $pdo->prepare("SELECT id, nombre FROM reporteros WHERE id = ? FOR UPDATE");
  $stmtR->execute([$reporteroId]);
  $r = $stmtR->fetch(PDO::FETCH_ASSOC);

  if (!$r) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'El reportero no existe']);
    exit;
  }

  $nombreReportero = trim((string)($r['nombre'] ?? ''));

  // Validación de traslape
  $fechaCita = !empty($n['fecha_cita']) ? (string)$n['fecha_cita'] : null;
  $limite = (int)($n['limite'] ?? 60);

  if ($fechaCita !== null) {
    $dtStart = new DateTime($fechaCita);
    $newStart = $dtStart->format('Y-m-d H:i:s');
    $newEnd   = (clone $dtStart)->modify('+' . $limite . ' minutes')->format('Y-m-d H:i:s');

    $chk = $pdo->prepare("
      SELECT
        id, noticia, fecha_cita,
        IFNULL(limite_tiempo_minutos, 60) AS limite,
        DATE_ADD(fecha_cita, INTERVAL IFNULL(limite_tiempo_minutos, 60) MINUTE) AS fecha_fin
      FROM noticias
      WHERE reportero_id = ?
        AND pendiente = 1
        AND fecha_cita IS NOT NULL
        AND fecha_cita < ?
        AND DATE_ADD(fecha_cita, INTERVAL IFNULL(limite_tiempo_minutos, 60) MINUTE) > ?
      ORDER BY fecha_cita ASC
      LIMIT 1
    ");
    $chk->execute([$reporteroId, $newEnd, $newStart]);
    $conf = $chk->fetch(PDO::FETCH_ASSOC);

    if ($conf) {
      $pdo->rollBack();
      http_response_code(409);
      echo json_encode([
        'success' => false,
        'code'    => 'cita_ocupada',
        'message' => 'El reportero ya cuenta con una cita a esta fecha / hora',
        'data'    => [
          'noticia_id' => (int)$conf['id'],
          'noticia'    => (string)$conf['noticia'],
          'fecha_cita' => (string)$conf['fecha_cita'],
          'fecha_fin'  => (string)$conf['fecha_fin'],
          'limite'     => (int)$conf['limite'],
        ],
      ]);
      exit;
    }
  }

  // Asignar
  $upd = $pdo->prepare("
    UPDATE noticias
    SET reportero_id = :rid, ultima_mod = NOW()
    WHERE id = :id AND reportero_id IS NULL
    LIMIT 1
  ");
  $upd->execute([':rid' => $reporteroId, ':id' => $noticiaId]);

  if ($upd->rowCount() <= 0) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'La noticia ya fue tomada por otro reportero']);
    exit;
  }

  // Notificación admin
  $tituloNoticia = trim((string)($n['noticia'] ?? 'Noticia'));
  $mensajeNotif = $nombreReportero !== ''
    ? "{$tituloNoticia} ha sido asignada a {$nombreReportero}."
    : "{$tituloNoticia} ha sido asignada a un reportero.";

  $stmtNotif = $pdo->prepare("
    INSERT INTO admin_notificaciones (
      tipo,
      noticia_id,
      reportero_id,
      mensaje,
      dedupe_key,
      created_at
    ) VALUES (
      'asignacion_noticia',
      :noticia_id,
      :reportero_id,
      :mensaje,
      NULL,
      NOW()
    )
  ");

  $stmtNotif->execute([
    ':noticia_id'   => $noticiaId,
    ':reportero_id' => $reporteroId,
    ':mensaje'      => $mensajeNotif,
  ]);

  $pdo->commit();

  echo json_encode([
    'success' => true,
    'message' => 'Noticia asignada correctamente',
  ]);
  exit;

} catch (Throwable $e) {
  if ($pdo->inTransaction()) {
    try { $pdo->rollBack(); } catch (Throwable $_) {}
  }
  http_response_code(500);
  error_log("tomar_noticia.php error: " . $e->getMessage());
  echo json_encode(['success' => false, 'message' => 'Error al tomar noticia']);
  exit;
}