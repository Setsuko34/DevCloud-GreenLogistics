import nodemailer from 'nodemailer'

interface ParcelEvent {
  parcel_id: string
  tracking_code: string
  event: string
  recipient_email: string
}

export function buildMailOptions(event: ParcelEvent) {
  const frontendUrl = process.env.FRONTEND_URL || 'http://app.greenlogistics.local'
  const trackingUrl = `${frontendUrl}/?code=${event.tracking_code}`

  return {
    from: process.env.NOTIFICATION_FROM || 'alerts@greenlogistics.local',
    to: event.recipient_email,
    subject: `GreenLogistics — Votre colis arrive dans 5 min !`,
    text: `Bonjour,\n\nVotre colis ${event.tracking_code} sera livré dans environ 5 minutes.\n\nSuivez-le en direct : ${trackingUrl}\n\nBonne journée,\nL'équipe GreenLogistics`
  }
}

export function createTransport() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'localhost',
    port: Number(process.env.SMTP_PORT) || 1025,
    secure: false
  })
}
