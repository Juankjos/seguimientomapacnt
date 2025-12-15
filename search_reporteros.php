<?php
require 'config.php';

$q = isset($_GET['q']) ? trim($_GET['q']) : '';

$sql = "
    SELECT id, nombre
    FROM reporteros
    WHERE role = 'reportero'
";

$params = [];

if ($q !== '') {
    $sql .= " AND nombre LIKE :q";
    $params[':q'] = '%' . $q . '%';
}

$sql .= " ORDER BY nombre ASC LIMIT 20";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows,
]);
