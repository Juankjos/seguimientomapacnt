<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$id = isset($_POST['id']) ? intval($_POST['id']) : 0;
$nombre = trim($_POST['nombre'] ?? '');
$apellidos = trim($_POST['apellidos'] ?? '');
$telefono = trim($_POST['telefono'] ?? '');
$email = trim($_POST['email'] ?? '');
$empresa = trim($_POST['empresa'] ?? '');
$dom1 = trim($_POST['domicilio_1'] ?? '');
$dom2 = trim($_POST['domicilio_2'] ?? '');
$dom3 = trim($_POST['domicilio_3'] ?? '');

if ($id <= 0) {
    echo json_encode(['success' => false, 'message' => 'id inválido']);
    exit;
}

if ($nombre === '') {
    echo json_encode(['success' => false, 'message' => 'El nombre es requerido']);
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

if ($telefono === '') $telefono = null;
if ($apellidos === '') $apellidos = null;
if ($empresa === '') $empresa = null;
if ($dom1 === '') $dom1 = null;
if ($dom2 === '') $dom2 = null;
if ($dom3 === '') $dom3 = null;

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare("
        SELECT usuario_id
        FROM clientes_clientes
        WHERE id = ?
        LIMIT 1
    ");
    $stmt->execute([$id]);
    $cliente = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$cliente) {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'Cliente no encontrado']);
        exit;
    }

    $usuarioId = intval($cliente['usuario_id']);

    $stmt = $pdo->prepare("
        UPDATE clientes_clientes
        SET
            nombre = :nombre,
            apellidos = :apellidos,
            telefono = :telefono,
            email = :email,
            empresa = :empresa,
            domicilio_1 = :dom1,
            domicilio_2 = :dom2,
            domicilio_3 = :dom3
        WHERE id = :id
        LIMIT 1
    ");
    $stmt->execute([
        ':id' => $id,
        ':nombre' => $nombre,
        ':apellidos' => $apellidos,
        ':telefono' => $telefono,
        ':email' => $email,
        ':empresa' => $empresa,
        ':dom1' => $dom1,
        ':dom2' => $dom2,
        ':dom3' => $dom3,
    ]);

    $stmt = $pdo->prepare("
        UPDATE usuarios_clientes
        SET email = :email
        WHERE id = :usuario_id
        LIMIT 1
    ");
    $stmt->execute([
        ':email' => $email,
        ':usuario_id' => $usuarioId,
    ]);

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
    $stmt->execute([$id]);
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
        'message' => 'Error al actualizar',
        'error' => $e->getMessage(),
    ]);
}