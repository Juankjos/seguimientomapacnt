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

// Auth (obtiene id y rol desde token)
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
  // 1) Verifica existencia y permiso
  if ($role === 'admin') {
    $stmt = $pdo->prepare("SELECT id, pendiente FROM noticias WHERE id = ? LIMIT 1");
    $stmt->execute([$noticiaId]);
  } else {
    $stmt = $pdo->prepare("SELECT id, pendiente FROM noticias WHERE id = ? AND reportero_id = ? LIMIT 1");
    $stmt->execute([$noticiaId, $userId]);
  }

  $row = $stmt->fetch(PDO::FETCH_ASSOC);
  if (!$row) {
    http_response_code(404);
    echo json_encode([
      'success' => false,
      'message' => 'Noticia no encontrada o no te pertenece',
      'code' => 'noticia_no_encontrada',
    ]);
    exit;
  }

  // 2) Actualiza: siempre toca ultima_mod para evitar rowCount=0 por “no cambios”
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

  echo json_encode([
    'success' => true,
    'message' => ((int)$row['pendiente'] === 1)
        ? 'Noticia eliminada de tus pendientes'
        : 'La noticia ya no estaba pendiente',
  ]);
  exit;

} catch (Throwable $e) {
  http_response_code(500);
  error_log("update_pendiente_noticia.php error: " . $e->getMessage());
  echo json_encode([
    'success' => false,
    'message' => 'Error al actualizar pendiente',
  ]);
  exit;
}
