<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$q = isset($_GET['q']) ? trim($_GET['q']) : '';

$sql = "
    SELECT id, nombre, role
    FROM reporteros
    WHERE 1=1
";

$params = [];

if ($q !== '') {
    $sql .= " AND nombre LIKE :q";
    $params[':q'] = '%' . $q . '%';
}

$sql .= " ORDER BY nombre ASC LIMIT 50";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows,
]);
