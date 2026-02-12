<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');
date_default_timezone_set('America/Mexico_City');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

$ws_token = isset($_POST['ws_token']) ? trim($_POST['ws_token']) : '';
$titulo = isset($_POST['titulo']) ? trim($_POST['titulo']) : '';
$descripcion = isset($_POST['descripcion']) ? trim($_POST['descripcion']) : '';
$vigencia = isset($_POST['vigencia']) ? trim($_POST['vigencia']) : ''; // YYYY-MM-DD

if ($ws_token === '' || $titulo === '' || $descripcion === '' || $vigencia === '') {
  echo json_encode(['success' => false, 'message' => 'Faltan campos requeridos']);
  exit;
}

// 1) Validar token + no expirado + role admin
$stmt = $pdo->prepare("
  SELECT id, role, ws_token_exp
  FROM reporteros
  WHERE ws_token = ?
  LIMIT 1
");
$stmt->execute([$ws_token]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
  echo json_encode(['success' => false, 'message' => 'No autorizado']);
  exit;
}

if ($user['role'] !== 'admin') {
  echo json_encode(['success' => false, 'message' => 'Solo admin']);
  exit;
}

$tz = new DateTimeZone('America/Mexico_City');
$now = new DateTime('now');
$exp = new DateTime($user['ws_token_exp']);
if ($now >= $exp) {
  echo json_encode(['success' => false, 'message' => 'Token expirado']);
  exit;
}

// 2) Vigencia: hasta fin de día
$vigDT = $vigencia . ' 23:59:59';

// 3) Insert
$stmt2 = $pdo->prepare("INSERT INTO avisos (titulo, descripcion, vigencia) VALUES (?, ?, ?)");
$stmt2->execute([$titulo, $descripcion, $vigDT]);

echo json_encode(['success' => true, 'message' => 'Aviso creado']);
exit;
