<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$token = isset($_POST['ws_token']) ? trim($_POST['ws_token']) : '';
if ($token === '') {
    echo json_encode(['success' => false, 'message' => 'ws_token requerido']);
    exit;
}

try {
    $stmt = $pdo->prepare("
        SELECT id, nombre, role, 
        puede_crear_noticias, 
        puede_ver_gestion_noticias,
        puede_ver_estadisticas,
        puede_ver_rastreo_general,
        puede_ver_empleado_mes,
        puede_ver_gestion,
        puede_ver_clientes, 
        puede_ver_tomar_noticias,
        ws_token_exp
        FROM reporteros
        WHERE ws_token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['success' => false, 'message' => 'Token inválido']);
        exit;
    }

    if (!empty($row['ws_token_exp'])) {
        $exp = strtotime($row['ws_token_exp']);
        if ($exp !== false && $exp < time()) {
            echo json_encode(['success' => false, 'message' => 'Token expirado']);
        exit;
        }
    }

    echo json_encode([
        'success' => true,
        'data' => [
            'id' => (int)$row['id'],
            'nombre' => $row['nombre'],
            'role' => $row['role'],
            'puede_crear_noticias' => (int)($row['puede_crear_noticias'] ?? 0),
            'puede_ver_gestion_noticias' => (int)($row['puede_ver_gestion_noticias'] ?? 0),
            'puede_ver_estadisticas'     => (int)($row['puede_ver_estadisticas'] ?? 0),
            'puede_ver_rastreo_general'  => (int)($row['puede_ver_rastreo_general'] ?? 0),
            'puede_ver_empleado_mes'     => (int)($row['puede_ver_empleado_mes'] ?? 0),
            'puede_ver_gestion'          => (int)($row['puede_ver_gestion'] ?? 0),
            'puede_ver_clientes'         => (int)($row['puede_ver_clientes'] ?? 0),
            'puede_ver_tomar_noticias'   => (int)($row['puede_ver_tomar_noticias'] ?? 0),
        ],
    ]);
    exit;

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener perfil',
        'error' => $e->getMessage(),
    ]);
    exit;
}
