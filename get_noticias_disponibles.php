<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

try {
    $sql = "
        SELECT
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Noticia') AS tipo_de_nota,
            n.descripcion,

            n.peticion_id,
            n.cliente_cliente_id,
            n.usuario_cliente_id,
            n.cliente_cliente_id AS cliente_id,

            COALESCE(
                NULLIF(TRIM(CONCAT_WS(' ', cc.nombre, cc.apellidos)), ''),
                uc.username,
                cc.email,
                uc.email
            ) AS cliente,

            -- alias viejo para no romper frontend existente
            cc.telefono AS cliente_whatsapp,

            -- campos nuevos más claros
            cc.telefono AS cliente_telefono,
            uc.email AS cliente_email,

            n.domicilio,
            n.fecha_pago,
            n.fecha_cita,
            n.latitud,
            n.longitud,
            n.limite_tiempo_minutos
        FROM noticias n
        LEFT JOIN clientes_clientes cc ON n.cliente_cliente_id = cc.id
        LEFT JOIN usuarios_clientes uc ON n.usuario_cliente_id = uc.id
        WHERE n.reportero_id IS NULL
          AND n.pendiente = 1
        ORDER BY n.id DESC
    ";

    $stmt = $pdo->query($sql);
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
        'message' => 'Error al obtener noticias disponibles',
        'error' => $e->getMessage(),
    ]);
    exit;
}