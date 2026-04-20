<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$clienteClienteId = isset($_GET['cliente_cliente_id']) ? intval($_GET['cliente_cliente_id']) : 0;
$usuarioClienteId = isset($_GET['usuario_cliente_id']) ? intval($_GET['usuario_cliente_id']) : 0;

// Compatibilidad con llamadas viejas: cliente_id -> cliente_cliente_id
if ($clienteClienteId <= 0 && isset($_GET['cliente_id'])) {
    $clienteClienteId = intval($_GET['cliente_id']);
}

if ($clienteClienteId <= 0 && $usuarioClienteId <= 0) {
    echo json_encode([
        'success' => false,
        'message' => 'Debes enviar cliente_cliente_id o usuario_cliente_id'
    ]);
    exit;
}

try {
    if ($clienteClienteId > 0) {
        $where = "n.cliente_cliente_id = ?";
        $param = $clienteClienteId;
    } else {
        $where = "n.usuario_cliente_id = ?";
        $param = $usuarioClienteId;
    }

    $sql = "
        SELECT
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Noticia') AS tipo_de_nota,
            n.descripcion,

            -- ids nuevos
            n.peticion_id,
            n.cliente_cliente_id,
            n.usuario_cliente_id,

            -- compatibilidad con apps viejas
            n.cliente_cliente_id AS cliente_id,

            n.domicilio,
            n.ubicacion_en_mapa,
            n.reportero_id,
            r.nombre AS reportero,
            n.fecha_pago,
            n.fecha_cita,
            n.pendiente,
            n.latitud,
            n.longitud,
            n.hora_llegada,
            n.tiempo_en_nota,
            n.ultima_mod,
            n.limite_tiempo_minutos,

            COALESCE(
                NULLIF(TRIM(CONCAT_WS(' ', cc.nombre, cc.apellidos)), ''),
                uc.username,
                cc.email,
                uc.email
            ) AS cliente,
            cc.telefono AS cliente_telefono,
            uc.email AS cliente_email
        FROM noticias n
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        LEFT JOIN clientes_clientes cc ON n.cliente_cliente_id = cc.id
        LEFT JOIN usuarios_clientes uc ON n.usuario_cliente_id = uc.id
        WHERE $where
        ORDER BY
            n.pendiente DESC,
            n.fecha_cita IS NULL,
            n.fecha_cita DESC,
            n.id DESC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$param]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'data' => $rows
    ]);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener noticias del cliente',
        'error' => $e->getMessage(),
    ]);
    exit;
}