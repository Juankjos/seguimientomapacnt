<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$id = intval($_GET['id'] ?? $_GET['cliente_id'] ?? 0);

if ($id <= 0) {
  echo json_encode(['success' => false, 'message' => 'id inválido']);
  exit;
}

$stmt = $pdo->prepare("SELECT id, nombre, whatsapp, domicilio FROM clientes WHERE id = ? LIMIT 1");
$stmt->execute([$id]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
  echo json_encode(['success' => false, 'message' => 'Cliente no encontrado']);
  exit;
}

echo json_encode(['success' => true, 'data' => $row]);