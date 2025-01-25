import axios from 'axios'

const token = process.env.PTERODACTYL_TOKEN
const serverId = process.env.PTERODACTYL_SERVER_IDENTIFIER
const baseUrl = process.env.PTERODACTYL_BASE_URL

const http = axios.create({
    baseURL: baseUrl,
    timeout: 1000,
    headers: {'Authorization': `Bearer ${token}`},
});

export async function sendCommand(command) {
    return await http.post(`/api/client/servers/${serverId}/command`, {
        'command': command,
    })
}