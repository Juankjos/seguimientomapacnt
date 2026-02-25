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
$whatsapp = trim($_POST['whatsapp'] ?? '');
$domicilio = trim($_POST['domicilio'] ?? '');

if ($id <= 0) {
    echo json_encode(['success' => false, 'message' => 'id inválido']);
    exit;
}
if ($nombre === '') {
    echo json_encode(['success' => false, 'message' => 'El nombre es requerido']);
    exit;
}

if ($whatsapp === '') {
    $whatsapp = null;
} else {
    // Quita espacios
    $whatsapp = preg_replace('/\s+/', '', $whatsapp);

    // Normaliza: permite '+' solo al inicio y solo dígitos después
    if (str_starts_with($whatsapp, '+')) {
        $digits = preg_replace('/\D/', '', substr($whatsapp, 1));
        $whatsapp = $digits === '' ? null : ('+' . $digits);
    } else {
        $digits = preg_replace('/\D/', '', $whatsapp);
        $whatsapp = $digits === '' ? null : $digits;
    }
}
$domicilio = ($domicilio === '') ? null : $domicilio;

try {
    $stmt = $pdo->prepare("
        UPDATE clientes
        SET nombre = :nombre,
            whatsapp = :whatsapp,
            domicilio = :domicilio
        WHERE id = :id
        LIMIT 1
    ");
    $stmt->execute([
        ':id' => $id,
        ':nombre' => $nombre,
        ':whatsapp' => $whatsapp,
        ':domicilio' => $domicilio,
    ]);

    $stmt2 = $pdo->prepare("SELECT id, nombre, whatsapp, domicilio FROM clientes WHERE id = ? LIMIT 1");
    $stmt2->execute([$id]);
    $row = $stmt2->fetch(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'data' => $row]);
} catch (Exception $e) {
    if (str_contains($e->getMessage(), 'uq_clientes_nombre')) {
        echo json_encode(['success' => false, 'message' => 'Ya existe un cliente con ese nombre']);
        exit;
    }
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al actualizar', 'error' => $e->getMessage()]);
}