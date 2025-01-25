import { exec } from 'node:child_process'
import { promisify } from 'util'

const execPromise = promisify(exec);

export async function execAsync(command) {
    try {
        const { stdout, stderr } = await execPromise(command);
        console.log('stdout:', stdout);
        console.log('stderr:', stderr);
    } catch (e) {
        console.error(e);
        throw e;
    }
}