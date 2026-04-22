<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$id = isset($_GET['id']) ? intval($_GET['id']) : 0;

if ($id <= 0) {
    echo json_encode(['success' => false, 'message' => 'id inválido']);
    exit;
}

try {
    $stmt = $pdo->prepare("
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
        WHERE c.id = ?
        LIMIT 1
    ");
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['success' => false, 'message' => 'Cliente no encontrado']);
        exit;
    }

    echo json_encode([
        'success' => true,
        'data' => $row,
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener cliente',
        'error' => $e->getMessage(),
    ]);
}