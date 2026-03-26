<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$q = isset($_GET['q']) ? trim($_GET['q']) : '';
$role = isset($_GET['role']) ? trim($_GET['role']) : '';

$sql = "
    SELECT id, nombre, nombre_pdf, role, 
        puede_crear_noticias,
        puede_ver_gestion_noticias,
        puede_ver_estadisticas,
        puede_ver_rastreo_general,
        puede_ver_empleado_mes,
        puede_ver_gestion,
        puede_ver_tomar_noticias,
        puede_ver_clientes,
        puede_editar_noticias,
        puede_ser_espectador_rutas,
        puede_modificar_ubicacion
    FROM reporteros
    WHERE 1=1
";

$params = [];

if ($q !== '') {
    $sql .= " AND nombre LIKE :q";
    $params[':q'] = '%' . $q . '%';
}

if ($role !== '') {
    if (!in_array($role, ['admin', 'reportero'], true)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'role inválido']);
        exit;
    }

    $sql .= " AND role = :role";
    $params[':role'] = $role;
}

$sql .= " ORDER BY nombre ASC LIMIT 50";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows,
]);
