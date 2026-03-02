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

$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

$user = require_auth($pdo, is_array($in) ? $in : []);

$roleServer = (string)($user['role'] ?? 'reportero');

if (!in_array($roleServer, ['admin', 'reportero'], true)) {
  http_response_code(403);
  echo json_encode(['success' => false, 'message' => 'Rol inválido']);
  exit;
}

$debugFcm  = (isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1');
$debugMail = (isset($_GET['debug_mail']) && $_GET['debug_mail'] === '1');

// Helpers
$noticia     = isset($in['noticia']) ? trim((string)$in['noticia']) : '';
$descripcion = isset($in['descripcion']) ? trim((string)$in['descripcion']) : '';
$domicilio   = isset($in['domicilio']) ? trim((string)$in['domicilio']) : '';
$fechaCita   = isset($in['fecha_cita']) ? trim((string)$in['fecha_cita']) : '';
$tipoDeNota  = isset($in['tipo_de_nota']) ? trim((string)$in['tipo_de_nota']) : 'Nota';

$limiteTiempoMinutos = 60;
if (isset($in['limite_tiempo_minutos']) && $in['limite_tiempo_minutos'] !== '') {
  $limiteTiempoMinutos = (int)$in['limite_tiempo_minutos'];
}
if ($limiteTiempoMinutos < 60) {
  echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos debe ser mínimo 60']);
  exit;
}
if ($limiteTiempoMinutos > 65535) {
  echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos excede el máximo permitido']);
  exit;
}

if ($tipoDeNota === '') $tipoDeNota = 'Nota';
$allowedTipos = ['Nota', 'Entrevista'];
if (!in_array($tipoDeNota, $allowedTipos, true)) {
  echo json_encode(['success' => false, 'message' => 'tipo_de_nota inválido (usa Nota o Entrevista)']);
  exit;
}

if ($noticia === '') {
  echo json_encode(['success' => false, 'message' => 'El campo noticia es obligatorio']);
  exit;
}

$reporteroId = null;
if (isset($in['reportero_id']) && $in['reportero_id'] !== '' && $in['reportero_id'] !== null) {
  $tmp = (int)$in['reportero_id'];
  if ($tmp > 0) $reporteroId = $tmp;
}

if ($roleServer !== 'admin') {
  $selfId = (int)($user['id'] ?? 0);

  if ($reporteroId !== null && $reporteroId !== $selfId) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'No puedes asignar noticias a otro reportero']);
    exit;
  }
  if ($reporteroId === null) $reporteroId = $selfId;
}

$clienteId = null;
if (isset($in['cliente_id']) && $in['cliente_id'] !== '' && $in['cliente_id'] !== null) {
  $tmp = (int)$in['cliente_id'];
  if ($tmp > 0) $clienteId = $tmp;
}

if ($clienteId !== null) {
  $chk = $pdo->prepare("SELECT 1 FROM clientes WHERE id = ? LIMIT 1");
  $chk->execute([$clienteId]);
  if (!$chk->fetchColumn()) {
    echo json_encode(['success' => false, 'message' => 'cliente_id no existe']);
    exit;
  }
}

$descripcionValue = ($descripcion !== '') ? $descripcion : null;
$domicilioValue   = ($domicilio !== '') ? $domicilio : null;

$fechaCitaValue = null;
if ($fechaCita !== '') {
  $fechaCita = str_replace('T', ' ', $fechaCita);
  $dt = DateTime::createFromFormat('Y-m-d H:i:s', $fechaCita) ?: DateTime::createFromFormat('Y-m-d H:i', $fechaCita);

  if (!$dt) {
    echo json_encode([
      'success' => false,
      'message' => 'fecha_cita inválida. Usa "YYYY-MM-DD HH:MM:SS" o "YYYY-MM-DDTHH:MM:SS".'
    ]);
    exit;
  }
  $fechaCitaValue = $dt->format('Y-m-d H:i:s');
}

try {
  $sql = "
    INSERT INTO noticias (
      noticia, tipo_de_nota, descripcion, cliente_id, domicilio, reportero_id, fecha_cita, pendiente, limite_tiempo_minutos
    ) VALUES (
      :noticia, :tipo_de_nota, :descripcion, :cliente_id, :domicilio, :reportero_id, :fecha_cita, 1, :limite_tiempo_minutos
    )
  ";

  $stmt = $pdo->prepare($sql);
  $stmt->execute([
    ':noticia'      => $noticia,
    ':tipo_de_nota' => $tipoDeNota,
    ':descripcion'  => $descripcionValue,
    ':domicilio'    => $domicilioValue,
    ':reportero_id' => $reporteroId,
    ':cliente_id'   => $clienteId, 
    ':fecha_cita'   => $fechaCitaValue,
    ':limite_tiempo_minutos' => $limiteTiempoMinutos,
  ]);

  $newId = (int)$pdo->lastInsertId();

  $fcmResult = null;
  $fcmError  = null;
  $topic     = null;

  try {
    $fcmPath = __DIR__ . '/fcm.php';
    if (!file_exists($fcmPath)) throw new Exception("FCM: no existe fcm.php");
    require_once $fcmPath;

    $topic = ($reporteroId === null) ? 'rol_reportero' : ('reportero_' . $reporteroId);

    $fcmResult = fcm_send_topic([
      'topic' => $topic,
      'title' => ($reporteroId === null) ? 'Nueva noticia disponible' : 'Nueva noticia',
      'body'  => $noticia,
      'data'  => [
        'tipo'       => ($reporteroId === null) ? 'noticia_sin_asignar' : 'nueva_noticia',
        'noticia_id' => (string)$newId,
      ],
    ]);
  } catch (Throwable $e) {
    $fcmError = $e->getMessage();
    error_log("FCM error: " . $fcmError);
  }

  $mailStatus = 'skipped';
  $mailError  = null;
  $mailTo     = null;

  try {
    if ($clienteId !== null) {
      $stmtC = $pdo->prepare("SELECT nombre, correo FROM clientes WHERE id = ? LIMIT 1");
      $stmtC->execute([$clienteId]);
      $c = $stmtC->fetch(PDO::FETCH_ASSOC);

      $nombreCliente = trim((string)($c['nombre'] ?? ''));
      $correoCliente = trim((string)($c['correo'] ?? ''));
      $mailTo = $correoCliente;
      $fechaCitaTxt = 'Sin cita programada';

      if (!empty($fechaCitaValue)) {
        $dtCita = new DateTime($fechaCitaValue, new DateTimeZone('America/Mexico_City'));
        if (class_exists('IntlDateFormatter')) {
          $fmt = new IntlDateFormatter(
            'es_MX',
            IntlDateFormatter::NONE,
            IntlDateFormatter::NONE,
            'America/Mexico_City',
            IntlDateFormatter::GREGORIAN,
            "dd 'de' MMMM 'de' yyyy 'A las' h:mm a"
          );
          $fechaCitaTxt = $fmt->format($dtCita);
        } else {
          $meses = [
            1=>'ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'
          ];
          $m = (int)$dtCita->format('n');
          $fechaCitaTxt = $dtCita->format('d') . '/' . ($meses[$m] ?? $dtCita->format('m')) . '/' . $dtCita->format('Y h:i A');
        }
      }
      if ($correoCliente === '') {
        $mailStatus = 'skipped_empty_email';
      } elseif (!filter_var($correoCliente, FILTER_VALIDATE_EMAIL)) {
        $mailStatus = 'skipped_invalid_email';
      } elseif (!is_array($mailCfg) || trim((string)($mailCfg['password'] ?? '')) === '') {
        $mailStatus = 'skipped_smtp_not_configured';
        error_log("MAIL skipped: SMTP_PASS vacío (noticia_id={$newId})");
      } else {
        $subject = 'Prueba';
        $body =
          "¡Hola," . ($nombreCliente !== '' ? " {$nombreCliente}!" : "!") . "\n\n" .
          "Tu cita quedó registrada.\n\n" .
          "Asunto: {$noticia}\n" .
          "Fecha: {$fechaCitaTxt} (Hora local)\n\n" .
          "¡Gracias por su preferencia!\nSoporte TVC Tepa";

        smtp_send_mail($mailCfg, $correoCliente, $nombreCliente, $subject, $body);
        $mailStatus = 'sent';
      }
    }
  } catch (Throwable $e) {
    $mailStatus = 'error';
    $mailError  = $e->getMessage();
    error_log("MAIL error noticia_id={$newId} cliente_id={$clienteId}: " . $mailError);
  }

  if ($debugFcm || $debugMail) {
    echo json_encode([
      'success' => true,
      'message' => 'Noticia creada (debug)',
      'id'      => $newId,

      'topic'     => $topic,
      'fcm'       => $fcmResult,
      'fcm_error' => $fcmError,

      'mail_status' => $mailStatus,
      'mail_to'     => $mailTo,
      'mail_error'  => $mailError,
    ]);
    exit;
  }

  echo json_encode(['success' => true, 'message' => 'Noticia creada correctamente', 'id' => $newId]);
  exit;

} catch (Throwable $e) {
  http_response_code(500);
  error_log("crear_noticia.php error: " . $e->getMessage());
  echo json_encode(['success' => false, 'message' => 'Error al crear noticia']);
  exit;
}
