<?php
declare(strict_types=1);

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require_once __DIR__ . '/vendor/autoload.php';

function smtp_send_mail(array $cfg, string $to, string $toName, string $subject, string $bodyText): void {
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
    $mail->Body    = $bodyText;
    $mail->AltBody = $bodyText;

    $mail->send();
}