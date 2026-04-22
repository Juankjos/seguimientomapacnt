<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$q = isset($_GET['q']) ? trim($_GET['q']) : '';

$sql = "
    SELECT
        c.id,
        c.usuario_id AS usuario_cliente_id,
        u.username,
        u.activo,
        c.nombre,
        c.apellidos,
        c.telefono,
        COALESCE(NULLIF(c.email, ''), u.email) AS email,
        c.empresa,
        c.domicilio_1,
        c.domicilio_2,
        c.domicilio_3
    FROM clientes_clientes c
    INNER JOIN usuarios_clientes u ON u.id = c.usuario_id
    WHERE 1 = 1
";

$params = [];

if ($q !== '') {
    $sql .= "
        AND (
            CONCAT_WS(' ', c.nombre, c.apellidos) LIKE :q
            OR u.username LIKE :q
            OR c.telefono LIKE :q
            OR c.email LIKE :q
            OR u.email LIKE :q
            OR c.empresa LIKE :q
        )
    ";
    $params[':q'] = '%' . $q . '%';
}

$sql .= "
    ORDER BY
        c.nombre ASC,
        c.apellidos ASC,
        u.username ASC
    LIMIT 200
";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo json_encode([
    'success' => true,
    'data'    => $rows,
]);