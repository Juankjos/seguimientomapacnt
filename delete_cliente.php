<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$clienteId = intval($_POST['id'] ?? $_POST['cliente_id'] ?? 0);
$wsToken = trim($_POST['ws_token'] ?? '');

// También acepta Authorization: Bearer <token>
if ($wsToken === '') {
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/Bearer\s+(.+)/i', $auth, $m)) {
        $wsToken = trim($m[1]);
    }
}

if ($clienteId <= 0) {
    echo json_encode(['success' => false, 'message' => 'id inválido']);
    exit;
}

if ($wsToken === '') {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'No autorizado']);
    exit;
}

try {
    // Validar usuario admin por ws_token
    $stmt = $pdo->prepare("
        SELECT id, nombre, role
        FROM reporteros
        WHERE ws_token = ?
          AND (ws_token_exp IS NULL OR ws_token_exp > NOW())
        LIMIT 1
    ");
    $stmt->execute([$wsToken]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Token inválido o expirado']);
        exit;
    }

    if (($user['role'] ?? '') !== 'admin') {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Sin permisos para eliminar clientes']);
        exit;
    }

    // Verificar que exista el cliente
    $stmt = $pdo->prepare("SELECT id, nombre FROM clientes WHERE id = ? LIMIT 1");
    $stmt->execute([$clienteId]);
    $cliente = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$cliente) {
        echo json_encode(['success' => false, 'message' => 'Cliente no encontrado']);
        exit;
    }

    // Bloquear borrado si tiene noticias ligadas
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM noticias WHERE cliente_id = ?");
    $stmt->execute([$clienteId]);
    $totalNoticias = (int)$stmt->fetchColumn();

    if ($totalNoticias > 0) {
        echo json_encode([
            'success' => false,
            'message' => 'No se puede eliminar el cliente porque tiene noticias asociadas',
            'data' => [
                'cliente_id' => $clienteId,
                'noticias_asociadas' => $totalNoticias,
            ],
        ]);
        exit;
    }

    $stmt = $pdo->prepare("DELETE FROM clientes WHERE id = ? LIMIT 1");
    $stmt->execute([$clienteId]);

    echo json_encode([
        'success' => true,
        'message' => 'Cliente eliminado correctamente',
        'data' => [
            'id' => $clienteId,
            'nombre' => $cliente['nombre'],
        ],
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al eliminar cliente',
        'error' => $e->getMessage(),
    ]);
}