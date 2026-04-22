<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$username = trim($_POST['username'] ?? '');
$nombre = trim($_POST['nombre'] ?? '');
$apellidos = trim($_POST['apellidos'] ?? '');
$telefono = trim($_POST['telefono'] ?? '');
$email = trim($_POST['email'] ?? '');
$empresa = trim($_POST['empresa'] ?? '');
$dom1 = trim($_POST['domicilio_1'] ?? '');
$dom2 = trim($_POST['domicilio_2'] ?? '');
$dom3 = trim($_POST['domicilio_3'] ?? '');
$password = trim($_POST['password'] ?? '');

if ($username === '') {
    echo json_encode(['success' => false, 'message' => 'El username es obligatorio']);
    exit;
}
if ($nombre === '') {
    echo json_encode(['success' => false, 'message' => 'El nombre es obligatorio']);
    exit;
}
if ($email === '') {
    echo json_encode(['success' => false, 'message' => 'El correo es obligatorio']);
    exit;
}
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    echo json_encode(['success' => false, 'message' => 'Correo inválido']);
    exit;
}
if ($password === '' || strlen($password) < 6) {
    echo json_encode(['success' => false, 'message' => 'La contraseña debe tener al menos 6 caracteres']);
    exit;
}

if ($apellidos === '') $apellidos = null;
if ($telefono === '') $telefono = null;
if ($empresa === '') $empresa = null;
if ($dom1 === '') $dom1 = null;
if ($dom2 === '') $dom2 = null;
if ($dom3 === '') $dom3 = null;

try {
    $pdo->beginTransaction();

    $hash = password_hash($password, PASSWORD_DEFAULT);

    $stmt = $pdo->prepare("
        INSERT INTO usuarios_clientes (
            username,
            email,
            password,
            rol,
            activo
        ) VALUES (
            :username,
            :email,
            :password,
            'cliente',
            1
        )
    ");
    $stmt->execute([
        ':username' => $username,
        ':email' => $email,
        ':password' => $hash,
    ]);

    $usuarioId = intval($pdo->lastInsertId());

    $stmt = $pdo->prepare("
        INSERT INTO clientes_clientes (
            usuario_id,
            nombre,
            apellidos,
            telefono,
            email,
            empresa,
            domicilio_1,
            domicilio_2,
            domicilio_3
        ) VALUES (
            :usuario_id,
            :nombre,
            :apellidos,
            :telefono,
            :email,
            :empresa,
            :dom1,
            :dom2,
            :dom3
        )
    ");
    $stmt->execute([
        ':usuario_id' => $usuarioId,
        ':nombre' => $nombre,
        ':apellidos' => $apellidos,
        ':telefono' => $telefono,
        ':email' => $email,
        ':empresa' => $empresa,
        ':dom1' => $dom1,
        ':dom2' => $dom2,
        ':dom3' => $dom3,
    ]);

    $clienteId = intval($pdo->lastInsertId());

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
    $stmt->execute([$clienteId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    $pdo->commit();

    echo json_encode(['success' => true, 'data' => $row]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }

    if (str_contains($e->getMessage(), 'Duplicate entry')) {
        echo json_encode([
            'success' => false,
            'message' => 'El username o correo ya existe',
        ]);
        exit;
    }

    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al crear cliente',
        'error' => $e->getMessage(),
    ]);
}