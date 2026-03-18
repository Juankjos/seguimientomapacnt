<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

// Lee JSON o FORM
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// Auth
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
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
  exit;
}

try {
  $pdo->beginTransaction();

  if ($role === 'admin') {
    $stmt = $pdo->prepare("
      SELECT
        n.id,
        n.pendiente,
        n.reportero_id,
        n.noticia,
        r.nombre AS reportero
      FROM noticias n
      LEFT JOIN reporteros r ON r.id = n.reportero_id
      WHERE n.id = ?
      LIMIT 1
      FOR UPDATE
    ");
    $stmt->execute([$noticiaId]);
  } else {
    $stmt = $pdo->prepare("
      SELECT
        n.id,
        n.pendiente,
        n.reportero_id,
        n.noticia,
        r.nombre AS reportero
      FROM noticias n
      LEFT JOIN reporteros r ON r.id = n.reportero_id
      WHERE n.id = ? AND n.reportero_id = ?
      LIMIT 1
      FOR UPDATE
    ");
    $stmt->execute([$noticiaId, $userId]);
  }

  $row = $stmt->fetch(PDO::FETCH_ASSOC);

  if (!$row) {
    $pdo->rollBack();
    http_response_code(404);
    echo json_encode([
      'success' => false,
      'message' => 'Noticia no encontrada o no te pertenece',
      'code' => 'noticia_no_encontrada',
    ]);
    exit;
  }

  $pendienteActual = (int)($row['pendiente'] ?? 0);
  $reporteroId = !empty($row['reportero_id']) ? (int)$row['reportero_id'] : null;
  $reporteroNombre = trim((string)($row['reportero'] ?? ''));
  $tituloNoticia = trim((string)($row['noticia'] ?? ''));

  if ($pendienteActual === 0) {
    $pdo->commit();
    echo json_encode([
      'success' => true,
      'message' => 'La noticia ya no estaba pendiente',
    ]);
    exit;
  }

  // 3) Cambio real: 1 -> 0
  if ($role === 'admin') {
    $up = $pdo->prepare("
      UPDATE noticias
      SET pendiente = 0, ultima_mod = NOW()
      WHERE id = ?
      LIMIT 1
    ");
    $up->execute([$noticiaId]);
  } else {
    $up = $pdo->prepare("
      UPDATE noticias
      SET pendiente = 0, ultima_mod = NOW()
      WHERE id = ? AND reportero_id = ?
      LIMIT 1
    ");
    $up->execute([$noticiaId, $userId]);
  }

  $mensajeNotif = '';
  if ($reporteroNombre !== '') {
    $mensajeNotif = "{$reporteroNombre} ha finalizado {$tituloNoticia}.";
  } else {
    $mensajeNotif = "Una noticia ha sido finalizada.";
  }

  $stmtNotif = $pdo->prepare("
    INSERT INTO admin_notificaciones (
      tipo,
      noticia_id,
      reportero_id,
      mensaje,
      created_at
    ) VALUES (
      'cierre_noticia',
      :noticia_id,
      :reportero_id,
      :mensaje,
      NOW()
    )
    ON DUPLICATE KEY UPDATE id = id
  ");

  $stmtNotif->execute([
    ':noticia_id'   => $noticiaId,
    ':reportero_id' => $reporteroId,
    ':mensaje'      => $mensajeNotif,
  ]);

  $pdo->commit();

  echo json_encode([
    'success' => true,
    'message' => 'Noticia eliminada de tus pendientes',
  ]);
  exit;

} catch (Throwable $e) {
  if ($pdo->inTransaction()) {
    try { $pdo->rollBack(); } catch (Throwable $_) {}
  }

  http_response_code(500);
  error_log("update_pendiente_noticia.php error: " . $e->getMessage());
  echo json_encode([
    'success' => false,
    'message' => 'Error al actualizar pendiente',
  ]);
  exit;
}
