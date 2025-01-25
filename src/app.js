import { exec } from 'node:child_process'
import { sendCommand } from './http.js'

exec('ls -la ./', (err, output) => {
    if (err) {
        console.error('Could not execute command: ', err)
        return
    }
    console.log('Output: \n', output)
})

const response = await sendCommand('list')
console.log(response)