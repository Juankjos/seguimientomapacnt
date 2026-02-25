<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$nombre = trim($_POST['nombre'] ?? '');
$whatsapp = trim($_POST['whatsapp'] ?? '');
$domicilio = trim($_POST['domicilio'] ?? '');
$password = trim($_POST['password'] ?? '');

if ($nombre === '') {
    echo json_encode(['success' => false, 'message' => 'El nombre es requerido']);
    exit;
}
if ($password === '' || strlen($password) < 6) {
    echo json_encode(['success' => false, 'message' => 'Password inválido (mínimo 6)']);
    exit;
}

$whatsapp = ($whatsapp === '') ? null : $whatsapp;
$domicilio = ($domicilio === '') ? null : $domicilio;

try {
    $hash = password_hash($password, PASSWORD_BCRYPT);
    $stmt = $pdo->prepare("
        INSERT INTO clientes (nombre, whatsapp, domicilio, password)
        VALUES (:nombre, :whatsapp, :domicilio, :password)
    ");
    $stmt->execute([
        ':nombre' => $nombre,
        ':whatsapp' => $whatsapp,
        ':domicilio' => $domicilio,
        ':password' => $hash,
    ]);

    $id = (int)$pdo->lastInsertId();

    echo json_encode([
        'success' => true,
        'data' => [
            'id' => $id,
            'nombre' => $nombre,
            'whatsapp' => $whatsapp,
            'domicilio' => $domicilio,
        ],
    ]);
} catch (Exception $e) {
    if (str_contains($e->getMessage(), 'uq_clientes_nombre')) {
        echo json_encode(['success' => false, 'message' => 'Ya existe un cliente con ese nombre']);
        exit;
    }
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al crear cliente', 'error' => $e->getMessage()]);
}