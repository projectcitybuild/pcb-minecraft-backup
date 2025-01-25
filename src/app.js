import { execAsync } from './utils.js'
import { sendCommand } from './http.js'

const b2KeyId = process.env.B2_KEY_ID
const b2ApplicationKey = process.env.B2_APPLICATION_KEY
const b2BucketName = process.env.B2_BUCKET_NAME
const dirToBackup = process.env.DIR_TO_BACKUP

// Note: B2 application key sometimes contain slashes. Since this entire
// string is a URI, the key specifically needs to be uri encoded
const b2Url = `b2://${b2KeyId}:${encodeURI(b2ApplicationKey)}@${b2BucketName}`

await execAsync(`
    duplicity backup \
        --full-if-older-than 7D \
        --verbosity 8 \
        ${dirToBackup} \
        ${b2Url}
`)

await execAsync(`
    duplicity verify \
        ${b2Url} \
        ${dirToBackup}
`)

// await execAsync(`
//     duplicity remove-older-than 30D \
//         --force \
//         ${b2Url}
// `)

// const response = await sendCommand('list')
// console.log(response)