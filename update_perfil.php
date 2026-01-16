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
$role        = isset($_POST['role']) ? trim($_POST['role']) : null;

$puedeCrearNoticias = null;
if (array_key_exists('puede_crear_noticias', $_POST)) {
    $v = trim((string)$_POST['puede_crear_noticias']);
    $vLower = strtolower($v);
    $puedeCrearNoticias = ($vLower === '1' || $vLower === 'true') ? 1 : 0;
}

if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

$nombre   = ($nombre !== null && $nombre !== '') ? $nombre : null;
$password = ($password !== null && $password !== '') ? $password : null;
$role     = ($role !== null && $role !== '') ? $role : null;

if ($role !== null && !in_array($role, ['reportero', 'admin'], true)) {
    echo json_encode(['success' => false, 'message' => 'Role inválido']);
    exit;
}

if ($password !== null && strlen($password) < 6) {
    echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
    exit;
}

if ($nombre === null && $password === null && $role === null && $puedeCrearNoticias === null) {
    echo json_encode(['success' => false, 'message' => 'No hay cambios para guardar']);
    exit;
}

try {
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

    if ($role !== null) {
        $updates[] = "role = :role";
        $params[':role'] = $role;
    }

    if ($puedeCrearNoticias !== null) {
        $updates[] = "puede_crear_noticias = :puede_crear_noticias";
        $params[':puede_crear_noticias'] = $puedeCrearNoticias;
    }

    $sql = "UPDATE reporteros SET " . implode(", ", $updates) . " WHERE id = :id LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    $stmt2 = $pdo->prepare("SELECT id, nombre, role, puede_crear_noticias FROM reporteros WHERE id = ? LIMIT 1");
    $stmt2->execute([$reporteroId]);
    $row = $stmt2->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'message' => 'Perfil actualizado',
        'data' => $row,
    ]);
    exit;

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar perfil',
        'error' => $e->getMessage(),
    ]);
    exit;
}
