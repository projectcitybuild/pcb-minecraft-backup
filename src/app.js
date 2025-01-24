const Rcon = require('rcon')
const { exec } = require('node:child_process')

exec('ls ./', (err, output) => {
    if (err) {
        console.error("could not execute command: ", err)
        return
    }
    console.log("Output: \n", output)
})

const options = {
    tcp: true, // Minecraft uses TCP
    challenge: false, // Minecraft does not use the Challenge protocol
};
client = new Rcon(host, port, password, options);