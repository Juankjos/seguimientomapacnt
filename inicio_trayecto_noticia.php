<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';
require __DIR__ . '/mailer.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

// Debug flags
$debugFcm  = (isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1');
$debugMail = (isset($_GET['debug_mail']) && $_GET['debug_mail'] === '1');

// Input JSON o form
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// Auth (no depende del rol, solo sesión válida)
$user = require_auth($pdo, is_array($in) ? $in : []);

$noticiaId = isset($in['noticia_id']) ? (int)$in['noticia_id'] : 0;
if ($noticiaId <= 0) {
  echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
  exit;
}

try {
  // Trae noticia + cliente + estado ruta
  $q = $pdo->prepare("
    SELECT
      n.id,
      n.noticia,
      n.cliente_id,
      n.fecha_cita,
      n.ruta_iniciada,
      n.ruta_iniciada_at,
      r.nombre AS reportero_nombre,
      c.nombre AS cliente_nombre,
      c.correo AS cliente_correo
    FROM noticias n
    LEFT JOIN reporteros r ON r.id = n.reportero_id
    LEFT JOIN clientes  c ON c.id = n.cliente_id
    WHERE n.id = :id
    LIMIT 1
  ");
  $q->execute([':id' => $noticiaId]);
  $row = $q->fetch(PDO::FETCH_ASSOC);

  if (!$row) {
    echo json_encode(['success' => false, 'message' => 'No existe la noticia']);
    exit;
  }

  $tituloNoticia = trim((string)($row['noticia'] ?? 'Noticia'));
  $nombreRep = trim((string)($row['reportero_nombre'] ?? ''));

  $clienteId = !empty($row['cliente_id']) ? (int)$row['cliente_id'] : null;
  $clienteNombre = trim((string)($row['cliente_nombre'] ?? ''));
  $clienteCorreo = trim((string)($row['cliente_correo'] ?? ''));

  $rutaIniciada = (int)($row['ruta_iniciada'] ?? 0);

  // ✅ Idempotencia: solo “iniciar” una vez
  $firstStart = false;
  if ($rutaIniciada === 0) {
    $up = $pdo->prepare("
      UPDATE noticias
      SET ruta_iniciada = 1,
          ruta_iniciada_at = COALESCE(ruta_iniciada_at, NOW())
      WHERE id = :id
      LIMIT 1
    ");
    $up->execute([':id' => $noticiaId]);
    $firstStart = true;
  }

  // -------------------- FCM a admins (igual que ya lo haces) --------------------
  $fcmRes = null;
  $fcmErr = null;

  try {
    $fcmPath = __DIR__ . '/fcm.php';
    if (!file_exists($fcmPath)) throw new Exception("No existe fcm.php");

    require_once $fcmPath;

    $body = $nombreRep !== ''
      ? "El reportero {$nombreRep} está en camino al destino."
      : "El reportero está en camino al destino.";

    $fcmRes = fcm_send_topic([
      'topic' => 'rol_admin',
      'title' => 'Reporte de trayecto',
      'body'  => $body . " ($tituloNoticia)",
      'data'  => [
        'tipo' => 'inicio_trayecto',
        'noticia_id' => (string)$noticiaId,
      ],
    ]);

    error_log("FCM inicio_trayecto rol_admin result=" . json_encode($fcmRes));
  } catch (Throwable $e) {
    $fcmErr = $e->getMessage();
    error_log("FCM inicio_trayecto error: " . $fcmErr);
  }

  // -------------------- MAIL a cliente (solo si fue primer inicio) --------------------
  $mailStatus = 'skipped';
  $mailError  = null;
  $mailTo     = null;

  try {
    if (!$firstStart) {
      $mailStatus = 'skipped_already_started';
    } elseif ($clienteId === null) {
      $mailStatus = 'skipped_no_cliente';
    } else {
      $mailTo = $clienteCorreo;

      if ($clienteCorreo === '') {
        $mailStatus = 'skipped_empty_email';
      } elseif (!filter_var($clienteCorreo, FILTER_VALIDATE_EMAIL)) {
        $mailStatus = 'skipped_invalid_email';
      } elseif (!is_array($mailCfg) || trim((string)($mailCfg['password'] ?? '')) === '') {
        $mailStatus = 'skipped_smtp_not_configured';
      } else {
        $fechaTxt = 'Sin cita programada';
        $fechaCitaDb = trim((string)($row['fecha_cita'] ?? ''));
        if ($fechaCitaDb !== '') {
          $dt = new DateTime($fechaCitaDb, new DateTimeZone('America/Mexico_City'));
          $fechaTxt = $dt->format('d/m/Y H:i') . ' (hora local)';
        }

        $subject = 'Tu reportero ya va en camino';
        $body =
          "Hola" . ($clienteNombre !== '' ? " {$clienteNombre}" : "") . ",\n\n" .
          "Tu reportero ya va en camino.\n\n" .
          "Asunto: {$tituloNoticia}\n" .
          "Cita: {$fechaTxt}\n" .
          "Estatus: En trayecto\n\n" .
          "Soporte TVC Tepa";

        smtp_send_mail($mailCfg, $clienteCorreo, $clienteNombre, $subject, $body);
        $mailStatus = 'sent';
      }
    }
  } catch (Throwable $e) {
    $mailStatus = 'error';
    $mailError = $e->getMessage();
    error_log("MAIL inicio_trayecto error noticia_id={$noticiaId}: " . $mailError);
  }

  // -------------------- RESPUESTA --------------------
  $out = [
    'success' => true,
    'message' => $firstStart ? 'Trayecto iniciado' : 'Trayecto ya iniciado (idempotente)',
  ];

  if ($debugFcm) {
    $out['fcm'] = $fcmRes;
    $out['fcm_error'] = $fcmErr;
  }
  if ($debugMail) {
    $out['mail_status'] = $mailStatus;
    $out['mail_to'] = $mailTo;
    $out['mail_error'] = $mailError;
  }

  echo json_encode($out);
  exit;

} catch (Throwable $e) {
  http_response_code(500);
  error_log("inicio_trayecto_noticia.php error: " . $e->getMessage());
  echo json_encode(['success' => false, 'message' => 'Error interno']);
  exit;
}