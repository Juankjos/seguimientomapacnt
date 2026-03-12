<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$nombre = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$passwordRaw = isset($_POST['password']) ? (string)$_POST['password'] : ''; // NO trim

if ($nombre === '' || $passwordRaw === '') {
    echo json_encode(['success' => false, 'message' => 'Nombre y contraseña son requeridos']);
    exit;
}

// 1) Buscar usuario
$stmt = $pdo->prepare('
    SELECT id, nombre, password, role, 
        puede_crear_noticias,
        puede_ver_gestion_noticias,
        puede_ver_estadisticas,
        puede_ver_rastreo_general,
        puede_ver_empleado_mes,
        puede_ver_gestion,
        puede_ver_tomar_noticias,
        puede_ver_clientes
    FROM reporteros
    WHERE nombre = ?
    LIMIT 1
');
$stmt->execute([$nombre]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

$authFail = function() {
    echo json_encode(['success' => false, 'message' => 'Credenciales inválidas']);
    exit;
};

if (!$user || !isset($user['password'])) {
    $authFail();
}

$stored = (string)$user['password'];

// 2) Validar contraseña + migración progresiva
$info = password_get_info($stored);
$isHashed = ($info['algo'] !== 0);

$ok = false;

if ($isHashed) {
    $ok = password_verify($passwordRaw, $stored);

    if ($ok && password_needs_rehash($stored, PASSWORD_DEFAULT)) {
        $newHash = password_hash($passwordRaw, PASSWORD_DEFAULT);
        if ($newHash !== false) {
            $upd = $pdo->prepare("UPDATE reporteros SET password = ? WHERE id = ? LIMIT 1");
            $upd->execute([$newHash, (int)$user['id']]);
        }
    }
} else {
    $ok = hash_equals($stored, $passwordRaw);

    if ($ok) {
        $newHash = password_hash($passwordRaw, PASSWORD_DEFAULT);
        if ($newHash === false) {
            http_response_code(500);
            echo json_encode(['success' => false, 'message' => 'Error interno']);
            exit;
        }
        $upd = $pdo->prepare("UPDATE reporteros SET password = ? WHERE id = ? LIMIT 1");
        $upd->execute([$newHash, (int)$user['id']]);
    }
}

if (!$ok) {
    $authFail();
}

// 3) Token de sesión
$token = bin2hex(random_bytes(32));
$exp = date('Y-m-d H:i:s', time() + (8 * 3600));

$stmtTok = $pdo->prepare("UPDATE reporteros SET ws_token = ?, ws_token_exp = ? WHERE id = ? LIMIT 1");
$stmtTok->execute([$token, $exp, (int)$user['id']]);

echo json_encode([
    'success'      => true,
    'message'      => 'Login correcto',
    'reportero_id' => (int)$user['id'],
    'nombre'       => $user['nombre'],
    'role'         => $user['role'],
    'ws_token'     => $token,
    'ws_token_exp' => $exp,
    'puede_crear_noticias'        => (int)($user['puede_crear_noticias'] ?? 0),
    'puede_ver_gestion_noticias'  => (int)($user['puede_ver_gestion_noticias'] ?? 0),
    'puede_ver_estadisticas'      => (int)($user['puede_ver_estadisticas'] ?? 0),
    'puede_ver_rastreo_general'   => (int)($user['puede_ver_rastreo_general'] ?? 0),
    'puede_ver_empleado_mes'      => (int)($user['puede_ver_empleado_mes'] ?? 0),
    'puede_ver_gestion'           => (int)($user['puede_ver_gestion'] ?? 0),
    'puede_ver_clientes'          => (int)($user['puede_ver_clientes'] ?? 0),
    'puede_ver_tomar_noticias'    => (int)($user['puede_ver_tomar_noticias'] ?? 0),
]);
exit;
