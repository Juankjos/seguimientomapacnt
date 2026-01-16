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
$role = isset($_POST['role']) ? trim($_POST['role']) : 'reportero';

$puedeCrearNoticias = 0;
if (array_key_exists('puede_crear_noticias', $_POST)) {
    $v = strtolower(trim((string)$_POST['puede_crear_noticias']));
    $puedeCrearNoticias = ($v === '1' || $v === 'true') ? 1 : 0;
}

if ($nombre === '' || $password === '') {
    echo json_encode(['success' => false, 'message' => 'Nombre y contraseña son requeridos']);
    exit;
}

if (strlen($password) < 6) {
    echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
    exit;
}

if ($role === '') $role = 'reportero';
if (!in_array($role, ['reportero', 'admin'], true)) {
    echo json_encode(['success' => false, 'message' => 'Role inválido']);
    exit;
}

try {
    $stmt0 = $pdo->prepare("SELECT id FROM reporteros WHERE nombre = ? LIMIT 1");
    $stmt0->execute([$nombre]);
    if ($stmt0->fetch()) {
        echo json_encode(['success' => false, 'message' => 'Ya existe un reportero con ese nombre']);
        exit;
    }

    $stmt = $pdo->prepare("
        INSERT INTO reporteros (nombre, password, role, puede_crear_noticias)
        VALUES (?, ?, ?, ?)
    ");
    $stmt->execute([$nombre, $password, $role, $puedeCrearNoticias]);

    $newId = (int)$pdo->lastInsertId();

    $stmt2 = $pdo->prepare("SELECT id, nombre, role, puede_crear_noticias FROM reporteros WHERE id = ? LIMIT 1");
    $stmt2->execute([$newId]);
    $row = $stmt2->fetch(PDO::FETCH_ASSOC);

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
