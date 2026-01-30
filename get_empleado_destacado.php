<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$anio = isset($_GET['anio']) ? intval($_GET['anio']) : intval(date('Y'));
$mes  = isset($_GET['mes'])  ? intval($_GET['mes'])  : intval(date('n'));

if ($anio < 2000 || $anio > 3000 || $mes < 1 || $mes > 12) {
  echo json_encode(['success' => false, 'message' => 'Parámetros anio/mes inválidos']);
  exit;
}

$minDefault = 10;

// 1) mínimo del mes
try {
  $stmt = $pdo->prepare("SELECT minimo FROM metas_noticias_mensuales WHERE anio=? AND mes=? LIMIT 1");
  $stmt->execute([$anio, $mes]);
  $row = $stmt->fetch();
  $minimo = $row ? intval($row['minimo']) : $minDefault;
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'Error al leer mínimo', 'error' => $e->getMessage()]);
  exit;
}

// 2) conteo por reportero
$sql = "
  SELECT
    r.id,
    r.nombre,
    TRIM(LOWER(r.`role`)) AS role,
    COALESCE(COUNT(n.id), 0) AS total
  FROM reporteros r
  LEFT JOIN noticias n
    ON n.reportero_id = r.id
   AND n.pendiente = 0
   AND n.hora_llegada IS NOT NULL
   AND YEAR(n.hora_llegada) = ?
   AND MONTH(n.hora_llegada) = ?
  WHERE TRIM(LOWER(r.`role`)) = 'reportero'
  GROUP BY r.id, r.nombre, role
  ORDER BY total DESC, r.nombre ASC
";

try {
  $stmt = $pdo->prepare($sql);
  $stmt->execute([$anio, $mes]);
  $rows = $stmt->fetchAll();

  echo json_encode([
    'success' => true,
    'data' => [
      'anio' => $anio,
      'mes' => $mes,
      'minimo' => $minimo,
      'reporteros' => $rows,
    ],
  ]);
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode([
    'success' => false,
    'message' => 'Error al obtener empleado destacado',
    'error' => $e->getMessage(),
  ]);
}
