<?php
declare(strict_types=1);

require 'config.php';
require 'require_auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

function toTinyInt($v): int {
    $s = strtolower(trim((string)$v));
    return ($s === '1' || $s === 'true' || $s === 'yes' || $s === 'si') ? 1 : 0;
}

$authUser = require_auth($pdo, $_POST);
$authId   = (int)($authUser['id'] ?? 0);
$authRole = (string)($authUser['role'] ?? 'reportero');
$isAdmin  = ($authRole === 'admin');

$reporteroId = isset($_POST['reportero_id']) ? (int)$_POST['reportero_id'] : 0;
if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

if (!$isAdmin && $reporteroId !== $authId) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Sin permiso para editar a otro usuario']);
    exit;
}

$nombre      = isset($_POST['nombre']) ? trim((string)$_POST['nombre']) : null;
$passwordRaw = array_key_exists('password', $_POST) ? (string)$_POST['password'] : null; // NO trim
$role        = isset($_POST['role']) ? trim((string)$_POST['role']) : null;

$nombre      = ($nombre !== null && $nombre !== '') ? $nombre : null;
$passwordRaw = ($passwordRaw !== null && $passwordRaw !== '') ? $passwordRaw : null;
$role        = ($role !== null && $role !== '') ? $role : null;

$puedeCrearNoticias = null;
if (array_key_exists('puede_crear_noticias', $_POST)) {
    $puedeCrearNoticias = toTinyInt($_POST['puede_crear_noticias']);
}

$menuPerms = [
    'puede_ver_gestion_noticias' => null,
    'puede_ver_estadisticas'     => null,
    'puede_ver_rastreo_general'  => null,
    'puede_ver_empleado_mes'     => null,
    'puede_ver_gestion'          => null,
    'puede_ver_clientes'         => null,
    'puede_ver_tomar_noticias'   => null,
];

foreach ($menuPerms as $k => $_) {
    if (array_key_exists($k, $_POST)) {
        $menuPerms[$k] = toTinyInt($_POST[$k]);
    }
}

if ($passwordRaw !== null && strlen($passwordRaw) < 6) {
    echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
    exit;
}

if ($role !== null && !in_array($role, ['reportero', 'admin'], true)) {
    echo json_encode(['success' => false, 'message' => 'Role inválido']);
    exit;
}

if (!$isAdmin) {
    if ($role !== null || $puedeCrearNoticias !== null) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Sin permiso para cambiar rol o permisos']);
        exit;
    }
    foreach ($menuPerms as $k => $v) {
        if ($v !== null) {
            http_response_code(403);
            echo json_encode(['success' => false, 'message' => 'Sin permiso para cambiar permisos de menú']);
            exit;
        }
    }
}

$updates = [];
$params  = [':id' => $reporteroId];

if ($nombre !== null) {
    $updates[] = "nombre = :nombre";
    $params[':nombre'] = $nombre;
}

if ($passwordRaw !== null) {
    $passwordHash = password_hash($passwordRaw, PASSWORD_DEFAULT);
    if ($passwordHash === false) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'No se pudo hashear la contraseña']);
        exit;
    }
    $updates[] = "password = :password";
    $params[':password'] = $passwordHash;
}

if ($isAdmin && $role !== null) {
    $updates[] = "role = :role";
    $params[':role'] = $role;
}

if ($isAdmin && $puedeCrearNoticias !== null) {
    $updates[] = "puede_crear_noticias = :puede_crear_noticias";
    $params[':puede_crear_noticias'] = $puedeCrearNoticias;
}

if ($isAdmin) {
    foreach ($menuPerms as $k => $v) {
        if ($v !== null) {
            $updates[] = "{$k} = :{$k}";
            $params[":{$k}"] = $v;
        }
    }
}

if (empty($updates)) {
    echo json_encode(['success' => false, 'message' => 'No hay cambios para guardar']);
    exit;
}

try {
    $sql = "UPDATE reporteros SET " . implode(", ", $updates) . " WHERE id = :id LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    $stmt2 = $pdo->prepare("
        SELECT id, nombre, role,
            puede_crear_noticias,
            puede_ver_gestion_noticias,
            puede_ver_estadisticas,
            puede_ver_rastreo_general,
            puede_ver_empleado_mes,
            puede_ver_gestion,
            puede_ver_tomar_noticias,
            puede_ver_clientes
        FROM reporteros
        WHERE id = ?
        LIMIT 1
    ");
    $stmt2->execute([$reporteroId]);
    $row = $stmt2->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'message' => 'Perfil actualizado',
        'data'    => $row,
    ]);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    error_log("update_perfil.php error: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar perfil',
    ]);
    exit;
}
