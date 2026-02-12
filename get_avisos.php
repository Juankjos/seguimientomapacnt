<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$ws_token = isset($_REQUEST['ws_token']) ? trim($_REQUEST['ws_token']) : '';
if ($ws_token === '') {
  echo json_encode(['success' => false, 'message' => 'No autorizado']);
  exit;
}

// Validar token no expirado
$stmt = $pdo->prepare("
  SELECT id, ws_token_exp
  FROM reporteros
  WHERE ws_token = ?
  LIMIT 1
");
$stmt->execute([$ws_token]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
  echo json_encode(['success' => false, 'message' => 'No autorizado']);
  exit;
}

$now = new DateTime('now');
$exp = new DateTime($user['ws_token_exp']);
if ($now >= $exp) {
  echo json_encode(['success' => false, 'message' => 'Token expirado']);
  exit;
}

// 1) Auto-eliminar avisos vencidos
$pdo->prepare("DELETE FROM avisos WHERE vigencia < NOW()")->execute();

// 2) Listar activos
$stmt2 = $pdo->query("SELECT id, titulo, descripcion, vigencia, created_at FROM avisos ORDER BY vigencia ASC");
$list = $stmt2->fetchAll(PDO::FETCH_ASSOC);

echo json_encode(['success' => true, 'data' => $list]);
exit;
