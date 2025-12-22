<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$nombre = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$password = isset($_POST['password']) ? trim($_POST['password']) : '';

if ($nombre === '' || $password === '') {
    echo json_encode(['success' => false, 'message' => 'Nombre y contraseña son requeridos']);
    exit;
}

if (strlen($password) < 6) {
    echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
    exit;
}

try {
    // Evitar duplicados por nombre
    $stmt0 = $pdo->prepare("SELECT id FROM reporteros WHERE nombre = ? LIMIT 1");
    $stmt0->execute([$nombre]);
    if ($stmt0->fetch()) {
        echo json_encode(['success' => false, 'message' => 'Ya existe un reportero con ese nombre']);
        exit;
    }

    $stmt = $pdo->prepare("INSERT INTO reporteros (nombre, password, role) VALUES (?, ?, 'reportero')");
    $stmt->execute([$nombre, $password]);

    $newId = (int)$pdo->lastInsertId();

    $stmt2 = $pdo->prepare("SELECT id, nombre, role FROM reporteros WHERE id = ? LIMIT 1");
    $stmt2->execute([$newId]);
    $row = $stmt2->fetch();

    echo json_encode([
        'success' => true,
        'message' => 'Reportero creado',
        'data' => $row,
    ]);
    exit;

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al crear reportero', 'error' => $e->getMessage()]);
    exit;
}
