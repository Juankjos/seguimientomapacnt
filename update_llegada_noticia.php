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

// INPUT JSON o FORM
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in   = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

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
$latitud   = isset($in['latitud']) ? (float)$in['latitud'] : null;
$longitud  = isset($in['longitud']) ? (float)$in['longitud'] : null;

if ($noticiaId <= 0) {
  echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
  exit;
}
if ($latitud === null || $longitud === null) {
  echo json_encode(['success' => false, 'message' => 'Latitud/longitud inválidas']);
  exit;
}

try {
  $pdo->beginTransaction();

  $stmt = $pdo->prepare("
    SELECT
      n.id,
      n.noticia,
      n.reportero_id,
      n.hora_llegada,
      n.llegada_latitud,
      n.llegada_longitud,
      n.ruta_iniciada,
      r.nombre AS reportero
    FROM noticias n
    LEFT JOIN reporteros r ON r.id = n.reportero_id
    WHERE n.id = ?
    LIMIT 1
    FOR UPDATE
  ");
  $stmt->execute([$noticiaId]);
  $actual = $stmt->fetch(PDO::FETCH_ASSOC);

  if (!$actual) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'Noticia no encontrada']);
    exit;
  }

  $repIdNoticia = (int)($actual['reportero_id'] ?? 0);

  if ($role === 'reportero' && $repIdNoticia > 0 && $repIdNoticia !== $userId) {
    $pdo->rollBack();
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'No puedes finalizar una ruta que no te pertenece']);
    exit;
  }

  $rutaIniciada = (int)($actual['ruta_iniciada'] ?? 0);
  if ($rutaIniciada !== 1) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'La ruta aún no ha sido iniciada']);
    exit;
  }

  if (!empty($actual['hora_llegada'])) {
    $stmtRow = $pdo->prepare("
      SELECT
        n.id,
        n.noticia,
        COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
        n.descripcion,
        n.cliente_id,
        c.nombre AS cliente,
        c.whatsapp AS cliente_whatsapp,
        n.domicilio,
        n.ubicacion_en_mapa,
        n.reportero_id,
        r.nombre AS reportero,
        n.fecha_pago,
        n.fecha_cita,
        n.fecha_cita_anterior,
        n.fecha_cita_cambios,
        n.latitud,
        n.longitud,
        n.hora_llegada,
        n.llegada_latitud,
        n.llegada_longitud,
        n.pendiente,
        n.ultima_mod,
        n.ruta_iniciada,
        n.ruta_iniciada_at,
        n.tiempo_en_nota,
        n.limite_tiempo_minutos
      FROM noticias n
      LEFT JOIN reporteros r ON n.reportero_id = r.id
      LEFT JOIN clientes c ON n.cliente_id = c.id
      WHERE n.id = ?
      LIMIT 1
    ");
    $stmtRow->execute([$noticiaId]);
    $row = $stmtRow->fetch(PDO::FETCH_ASSOC);

    $pdo->commit();
    echo json_encode([
      'success' => true,
      'message' => 'Llegada ya registrada (idempotente)',
      'data' => $row,
    ]);
    exit;
  }

  $ahora = date('Y-m-d H:i:s');

  $up = $pdo->prepare("
    UPDATE noticias
    SET
      hora_llegada = :hora_llegada,
      llegada_latitud = :latitud,
      llegada_longitud = :longitud,
      ultima_mod = :ultima_mod
    WHERE id = :id
    LIMIT 1
  ");
  $up->execute([
    ':hora_llegada' => $ahora,
    ':latitud' => $latitud,
    ':longitud' => $longitud,
    ':ultima_mod' => $ahora,
    ':id' => $noticiaId,
  ]);

  $reporteroNombreNotif = trim((string)($actual['reportero'] ?? ''));
  $mensajeNotif = $reporteroNombreNotif !== ''
    ? "{$reporteroNombreNotif}' ha finalizado su ruta."
    : "El reportero ha finalizado su ruta.";

  $stmtNotif = $pdo->prepare("
    INSERT INTO admin_notificaciones (
      tipo,
      noticia_id,
      reportero_id,
      mensaje,
      created_at
    ) VALUES (
      'fin_ruta',
      :noticia_id,
      :reportero_id,
      :mensaje,
      NOW()
    )
    ON DUPLICATE KEY UPDATE id = id
  ");

  $stmtNotif->execute([
    ':noticia_id'   => $noticiaId,
    ':reportero_id' => $repIdNoticia > 0 ? $repIdNoticia : null,
    ':mensaje'      => $mensajeNotif,
  ]);

  $stmtRow = $pdo->prepare("
    SELECT
      n.id,
      n.noticia,
      COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
      n.descripcion,
      n.cliente_id,
      c.nombre AS cliente,
      c.whatsapp AS cliente_whatsapp,
      n.domicilio,
      n.ubicacion_en_mapa,
      n.reportero_id,
      r.nombre AS reportero,
      n.fecha_pago,
      n.fecha_cita,
      n.fecha_cita_anterior,
      n.fecha_cita_cambios,
      n.latitud,
      n.longitud,
      n.hora_llegada,
      n.llegada_latitud,
      n.llegada_longitud,
      n.pendiente,
      n.ultima_mod,
      n.ruta_iniciada,
      n.ruta_iniciada_at,
      n.tiempo_en_nota,
      n.limite_tiempo_minutos
    FROM noticias n
    LEFT JOIN reporteros r ON n.reportero_id = r.id
    LEFT JOIN clientes c ON n.cliente_id = c.id
    WHERE n.id = ?
    LIMIT 1
  ");
  $stmtRow->execute([$noticiaId]);
  $row = $stmtRow->fetch(PDO::FETCH_ASSOC);

  $pdo->commit();

  echo json_encode([
    'success' => true,
    'message' => 'Llegada registrada',
    'data' => $row,
  ]);
  exit;

} catch (Throwable $e) {
  if ($pdo->inTransaction()) {
    try { $pdo->rollBack(); } catch (Throwable $_) {}
  }

  http_response_code(500);
  error_log("update_llegada_noticia.php error: " . $e->getMessage());
  echo json_encode([
    'success' => false,
    'message' => 'Error interno',
  ]);
  exit;
}