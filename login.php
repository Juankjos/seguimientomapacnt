<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$nombre   = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$password = isset($_POST['password']) ? trim($_POST['password']) : '';

if ($nombre === '' || $password === '') {
    echo json_encode(['success' => false, 'message' => 'Nombre y contraseña son requeridos']);
    exit;
}

// 1) Buscar usuario
$stmt = $pdo->prepare('SELECT id, nombre, password, role FROM reporteros WHERE nombre = ? LIMIT 1');
$stmt->execute([$nombre]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    echo json_encode(['success' => false, 'message' => 'Usuario no encontrado']);
    exit;
}

// 2) Validar contraseña (PLANO - no recomendado)
if ($password !== $user['password']) {
    echo json_encode(['success' => false, 'message' => 'Contraseña incorrecta']);
    exit;
}

/*
// ✅ Si usas password_hash en la BD, usa esto:
// if (!password_verify($password, $user['password'])) {
//     echo json_encode(['success' => false, 'message' => 'Contraseña incorrecta']);
//     exit;
// }
*/

// 3) Generar token y guardarlo (YA con id válido)
$token = bin2hex(random_bytes(32));
$exp = date('Y-m-d H:i:s', time() + 86400); // 24h

$stmtTok = $pdo->prepare("UPDATE reporteros SET ws_token = ?, ws_token_exp = ? WHERE id = ?");
$stmtTok->execute([$token, $exp, (int)$user['id']]);

echo json_encode([
    'success'      => true,
    'message'      => 'Login correcto',
    'reportero_id' => (int)$user['id'],
    'nombre'       => $user['nombre'],
    'role'         => $user['role'],
    'ws_token'     => $token,
    'ws_token_exp' => $exp,
]);
exit;
