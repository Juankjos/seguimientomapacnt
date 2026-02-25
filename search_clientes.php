<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$q = isset($_GET['q']) ? trim($_GET['q']) : '';

$sql = "SELECT id, nombre, whatsapp, domicilio FROM clientes WHERE 1=1";
$params = [];

if ($q !== '') {
  $sql .= " AND nombre LIKE :q";
  $params[':q'] = '%' . $q . '%';
}

$sql .= " ORDER BY nombre ASC LIMIT 200";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo json_encode([
  'success' => true,
  'data'    => $rows,
]);