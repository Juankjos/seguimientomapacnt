<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$anio   = isset($_POST['anio']) ? intval($_POST['anio']) : 0;
$mes    = isset($_POST['mes']) ? intval($_POST['mes']) : 0;
$minimo = isset($_POST['minimo']) ? intval($_POST['minimo']) : -1;

$role = isset($_POST['role']) ? trim($_POST['role']) : '';
$updatedBy = isset($_POST['updated_by']) ? intval($_POST['updated_by']) : null;

if ($role !== 'admin') {
  http_response_code(403);
  echo json_encode(['success' => false, 'message' => 'No autorizado']);
  exit;
}

if ($anio < 2000 || $anio > 3000 || $mes < 1 || $mes > 12 || $minimo < 0) {
  echo json_encode(['success' => false, 'message' => 'Parámetros inválidos']);
  exit;
}

try {
  $sql = "
    INSERT INTO metas_noticias_mensuales (anio, mes, minimo, updated_by)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      minimo = VALUES(minimo),
      updated_by = VALUES(updated_by),
      updated_at = CURRENT_TIMESTAMP
  ";

  $stmt = $pdo->prepare($sql);
  $stmt->execute([$anio, $mes, $minimo, $updatedBy]);

  echo json_encode(['success' => true, 'message' => 'Mínimo actualizado']);
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'Error al guardar mínimo', 'error' => $e->getMessage()]);
}
