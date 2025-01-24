import { Rcon } from 'rcon-client'
import { exec } from 'node:child_process'

exec('ls -la ./', (err, output) => {
    if (err) {
        console.error('Could not execute command: ', err)
        return
    }
    console.log('Output: \n', output)
})

const rcon = await Rcon.connect({
    host: process.env.RCON_HOST,
    port: process.env.RCON_PORT,
    password: process.env.RCON_PASSWORD,
})

console.log(await rcon.send("list"))

rcon.end()