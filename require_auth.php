<?php
declare(strict_types=1);

function require_auth(PDO $pdo, array $in = []): array {
    $token = '';

    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/Bearer\s+(.+)/i', $authHeader, $m)) {
        $token = trim($m[1]);
    }

    if ($token === '' && isset($in['ws_token'])) {
        $token = trim((string)$in['ws_token']);
    }

    if ($token === '' && isset($_POST['ws_token'])) {
        $token = trim((string)$_POST['ws_token']);
    }

    if ($token === '' || !preg_match('/^[a-f0-9]{64}$/i', $token)) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'No autorizado']);
        exit;
    }

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
            AND ws_token_exp > NOW()
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Sesión expirada o inválida']);
        exit;
    }

    return $user;
}