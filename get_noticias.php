<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

$modo = isset($_GET['modo']) ? $_GET['modo'] : 'reportero';

function noticiasSelectBase(): string {
    return "
        SELECT
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Noticia') AS tipo_de_nota,
            n.descripcion,

            n.peticion_id,
            n.cliente_cliente_id,
            n.usuario_cliente_id,

            -- alias de compatibilidad para frontend viejo
            n.cliente_cliente_id AS cliente_id,

            COALESCE(
                NULLIF(TRIM(CONCAT_WS(' ', cc.nombre, cc.apellidos)), ''),
                uc.username,
                cc.email,
                uc.email
            ) AS cliente,

            -- alias viejo para no romper vistas existentes
            cc.telefono AS cliente_whatsapp,

            -- campos nuevos más claros
            cc.telefono AS cliente_telefono,
            cc.email AS cliente_email,
            uc.username AS cliente_username,
            uc.email AS usuario_email,

            n.domicilio,
            n.ubicacion_en_mapa,
            n.reportero_id,
            COALESCE(NULLIF(TRIM(r.nombre_pdf), ''), r.nombre) AS reportero,
            n.fecha_pago,
            n.fecha_cita,
            n.fecha_cita_anterior,
            n.fecha_cita_cambios,
            n.latitud,
            n.longitud,
            n.hora_llegada,
            n.llegada_latitud,
            n.llegada_longitud,
            n.pendiente,
            n.ruta_iniciada,
            n.ruta_iniciada_at,
            n.ultima_mod,
            n.tiempo_en_nota,
            n.limite_tiempo_minutos
        FROM noticias n
        LEFT JOIN clientes_clientes cc ON n.cliente_cliente_id = cc.id
        LEFT JOIN usuarios_clientes uc ON n.usuario_cliente_id = uc.id
        LEFT JOIN reporteros r ON n.reportero_id = r.id
    ";
}

if ($modo === 'admin') {
    $sql = noticiasSelectBase() . "
        ORDER BY
            n.fecha_cita IS NULL,
            n.fecha_cita ASC,
            n.id ASC
    ";

    try {
        $stmt = $pdo->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'success' => true,
            'data'    => $rows,
        ]);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'message' => 'Error al obtener noticias (admin)',
            'error'   => $e->getMessage(),
        ]);
    }
    exit;
}

$reporteroId = isset($_GET['reportero_id']) ? intval($_GET['reportero_id']) : 0;
$incluyeCerradas = isset($_GET['incluye_cerradas']) && $_GET['incluye_cerradas'] == '1';

if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

$sql = noticiasSelectBase() . "
    WHERE n.reportero_id = ?
";

if (!$incluyeCerradas) {
    $sql .= " AND n.pendiente = 1 ";
}

$sql .= "
    ORDER BY
        n.pendiente DESC,
        n.fecha_cita IS NULL,
        n.fecha_cita ASC,
        n.id ASC
";

try {
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$reporteroId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'data'    => $rows,
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener noticias (reportero)',
        'error'   => $e->getMessage(),
    ]);
}
