<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$nombre   = isset($_POST['nombre'])   ? trim($_POST['nombre'])   : '';
$password = isset($_POST['password']) ? trim($_POST['password']) : '';

if ($nombre === '' || $password === '') {
    echo json_encode(['success' => false, 'message' => 'Nombre y contraseña son requeridos']);
    exit;
}

$stmt = $pdo->prepare('SELECT id, nombre, password FROM reporteros WHERE nombre = ? LIMIT 1');
$stmt->execute([$nombre]);
$user = $stmt->fetch();

if (!$user) {
    echo json_encode(['success' => false, 'message' => 'Usuario no encontrado']);
    exit;
}

// 🔐 Si guardas el password plano (no recomendado), usa comparación directa:
if ($password !== $user['password']) {
    echo json_encode(['success' => false, 'message' => 'Contraseña incorrecta']);
    exit;
}

/*
// ✅ Si usas password_hash en la BD, descomenta esto y usa password_verify:
if (!password_verify($password, $user['password'])) {
    echo json_encode(['success' => false, 'message' => 'Contraseña incorrecta']);
    exit;
}
*/

echo json_encode([
    'success'      => true,
    'message'      => 'Login correcto',
    'reportero_id' => $user['id'],
    'nombre'       => $user['nombre'],
]);
