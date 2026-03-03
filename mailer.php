<?php
declare(strict_types=1);

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require_once __DIR__ . '/vendor/autoload.php';

function smtp_send_mail(
    array $cfg,
    string $to,
    string $toName,
    string $subject,
    string $bodyText,
    ?string $bodyHtml = null
): void {
    $mail = new PHPMailer(true);

    $mail->isSMTP();
    $mail->Host       = $cfg['host'];
    $mail->Port       = (int)$cfg['port'];
    $mail->SMTPAuth   = true;
    $mail->Username   = $cfg['username'];
    $mail->Password   = $cfg['password'];
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;

    $mail->CharSet = 'UTF-8';

    $mail->setFrom($cfg['from_email'], $cfg['from_name']);
    $mail->addAddress($to, $toName);

    $mail->Subject = $subject;

    if ($bodyHtml !== null && trim($bodyHtml) !== '') {
        $mail->isHTML(true);
        $mail->Body    = $bodyHtml;
        $mail->AltBody = $bodyText;
    } else {
        $mail->isHTML(false);
        $mail->Body    = $bodyText;
        $mail->AltBody = $bodyText;
    }

    $mail->send();
}

function email_template_html(array $data): string {
    $brand = htmlspecialchars((string)($data['brand'] ?? 'Televisión Por Cable Tepa'), ENT_QUOTES, 'UTF-8');
    $title = htmlspecialchars((string)($data['title'] ?? 'Notificación'), ENT_QUOTES, 'UTF-8');
    $greet = htmlspecialchars((string)($data['greeting'] ?? 'Hola'), ENT_QUOTES, 'UTF-8');
    $intro = htmlspecialchars((string)($data['intro'] ?? ''), ENT_QUOTES, 'UTF-8');

    $details = $data['details'] ?? [];
    if (!is_array($details)) $details = [];

    $preheader = htmlspecialchars((string)($data['preheader'] ?? ''), ENT_QUOTES, 'UTF-8');

    $rowsHtml = '';
    foreach ($details as $row) {
        $label = htmlspecialchars((string)($row[0] ?? ''), ENT_QUOTES, 'UTF-8');
        $value = htmlspecialchars((string)($row[1] ?? ''), ENT_QUOTES, 'UTF-8');

        if ($label === '' && $value === '') continue;

        $rowsHtml .= '
        <tr>
            <td style="padding:10px 12px;border-bottom:1px solid #eee;color:#555;width:160px;font-weight:600;">'.$label.'</td>
            <td style="padding:10px 12px;border-bottom:1px solid #eee;color:#222;">'.$value.'</td>
        </tr>';
    }

    $footer = htmlspecialchars((string)($data['footer'] ?? $brand), ENT_QUOTES, 'UTF-8');

    return '<!doctype html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="x-apple-disable-message-reformatting">
    <title>'.$title.'</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f8;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">'.$preheader.'</div>

    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f6f8;padding:24px 0;">
        <tr>
        <td align="center">
            <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:600px;max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;">
            <tr>
                <td style="background:#0f172a;color:#ffffff;padding:18px 22px;font-family:Arial,Helvetica,sans-serif;">
                <div style="font-size:14px;opacity:.9;">'.$brand.'</div>
                <div style="font-size:20px;font-weight:700;line-height:1.2;margin-top:6px;">'.$title.'</div>
                </td>
            </tr>

            <tr>
                <td style="padding:22px;font-family:Arial,Helvetica,sans-serif;color:#111827;">
                <div style="font-size:16px;line-height:1.5;margin:0 0 10px 0;"><strong>'.$greet.'</strong></div>
                '.($intro !== '' ? '<div style="font-size:14px;line-height:1.6;color:#374151;margin:0 0 14px 0;">'.$intro.'</div>' : '').'
                
                '.($rowsHtml !== '' ? '
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border:1px solid #eee;border-radius:10px;overflow:hidden;">
                    '.$rowsHtml.'
                </table>' : '').'

                <div style="font-size:12px;line-height:1.6;color:#6b7280;margin-top:16px;">
                    Si no reconoces este correo o crees que es un error, puedes ignorarlo.
                </div>
                </td>
            </tr>

            <tr>
                <td style="background:#f8fafc;padding:14px 22px;font-family:Arial,Helvetica,sans-serif;color:#6b7280;font-size:12px;">
                '.$footer.'
                </td>
            </tr>
            </table>

            <div style="font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#9ca3af;margin-top:10px;">
            Este mensaje fue enviado automáticamente. Por favor no respondas a este correo.
            </div>
        </td>
        </tr>
    </table>
</body>
</html>';
}