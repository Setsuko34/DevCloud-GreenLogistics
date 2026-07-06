import { FastifyInstance } from 'fastify'

export async function wsRoutes(app: FastifyInstance) {
  app.get('/positions', { websocket: true }, (socket) => {
    app.positionClients.add(socket)
    socket.on('close', () => app.positionClients.delete(socket))
  })
}
