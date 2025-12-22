<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$reporteroId = isset($_POST['reportero_id']) ? intval($_POST['reportero_id']) : 0;
$nombre      = isset($_POST['nombre']) ? trim($_POST['nombre']) : null;
$password    = isset($_POST['password']) ? trim($_POST['password']) : null;

if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

$nombre   = ($nombre !== null && $nombre !== '') ? $nombre : null;
$password = ($password !== null && $password !== '') ? $password : null;

if ($nombre === null && $password === null) {
    echo json_encode(['success' => false, 'message' => 'No hay cambios para guardar']);
    exit;
}

try {
    if ($password !== null && strlen($password) < 6) {
        echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
        exit;
    }

    $updates = [];
    $params = [':id' => $reporteroId];

    if ($nombre !== null) {
        $updates[] = "nombre = :nombre";
        $params[':nombre'] = $nombre;
    }

    if ($password !== null) {
        $updates[] = "password = :password";
        $params[':password'] = $password;
    }

    $sql = "UPDATE reporteros SET " . implode(", ", $updates) . " WHERE id = :id LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    $stmt2 = $pdo->prepare("SELECT id, nombre, role FROM reporteros WHERE id = ? LIMIT 1");
    $stmt2->execute([$reporteroId]);
    $row = $stmt2->fetch();

    echo json_encode([
        'success' => true,
        'message' => 'Perfil actualizado',
        'data' => $row,
    ]);
    } catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar perfil',
        'error' => $e->getMessage(),
    ]);
}
