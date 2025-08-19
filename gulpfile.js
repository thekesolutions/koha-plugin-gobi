const { dest, series, src } = require('gulp');
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const fs = require('fs');
const dateTime = require('node-datetime');
const Vinyl = require('vinyl');
const path = require('path');
const stream = require('stream');

const dt = dateTime.create();
const today = dt.format('Y-m-d');

const package_json = JSON.parse(fs.readFileSync('./package.json'));
const release_filename = `${package_json.name}-v${package_json.version}.kpz`;

const pm_name = 'GOBI';
const pm_file = pm_name + '.pm';
const pm_file_path = path.join('Koha', 'Plugin', 'Com', 'Theke');
const pm_file_path_full = path.join(pm_file_path, pm_file);
const pm_file_path_dist = path.join('dist', pm_file_path);
const pm_file_path_full_dist = path.join(pm_file_path_dist, pm_file);
const pm_bundle_path = path.join(pm_file_path, pm_name);

/**
 * Array of directories relative to pm_bundle_path where static files will be served
 * If no static files need to be served, set static_relative_path = []
 */
const static_relative_path = [];

var static_absolute_path = [];

if (static_relative_path.length) {
    static_absolute_path = static_relative_path.map(dir => path.join(pm_bundle_path, dir) + '/**/*');
}

console.log('Building:', release_filename);
console.log('Target:', pm_file_path_full_dist);

function static(cb) {
    if (static_absolute_path.length) {
        let spec_body = JSON.stringify({
            get: {
                'x-mojo-to': 'Static#get',
                tags: ['pluginStatic'],
                responses: {
                    200: {
                        description: 'File found',
                        schema: {
                            type: 'file'
                        }
                    },
                    404: {
                        description: 'File not found',
                        schema: {
                            type: 'object',
                            properties: {
                                error: {
                                    description: "An explanation for the error",
                                    type: "string"
                                }
                            }
                        }
                    },
                    400: {
                        description: 'Bad request',
                        schema: {
                            type: 'object',
                            properties: {
                                error: {
                                    description: "An explanation for the error",
                                    type: "string"
                                }
                            }
                        }
                    },
                    500: {
                        description: 'Internal server error',
                        schema: {
                            type: 'object',
                            properties: {
                                error: {
                                    description: "An explanation for the error",
                                    type: "string"
                                }
                            }
                        }
                    }
                }
            }
        }, null, 2);

        return src(static_absolute_path)
            .pipe(new stream.Transform({
                objectMode: true,
                transform: (file, unused, cb) => {
                    if (file.stat.isDirectory()) return cb();
                    let path_name = path.join('/', path.relative(pm_bundle_path, file.base), file.relative);
                    console.log('Creating static endpoint:', path_name);
                    let endpoint_spec = '"' + path_name + '": ' + spec_body;
                    file.contents = Buffer.from(endpoint_spec);
                    cb(null, file);
                }
            }))
            .pipe(new stream.Transform({
                objectMode: true,
                transform: function (file, unused, cb) {
                    !this.bufArray && (this.bufArray = []);
                    this.bufArray.push(file.contents);
                    cb();
                }
            }))
            .on('finish', function () {
                let file = new Vinyl({
                    path: 'staticapi.json',
                    contents: Buffer.from('{\n' + this.bufArray.map(buf => buf.toString()).join(',\n') + '\n}')
                });
                this.emit('data', file);
                this.end();
            })
            .pipe(dest(pm_bundle_path));
    } else {
        console.log('No static files to process');
        cb();
    }
}

async function build() {
    try {
        console.log('=== Starting Build Process ===');
        
        // Create dist directory
        console.log('Creating dist directory...');
        await execPromise('mkdir -p dist');
        
        // Copy Koha directory
        console.log('Copying plugin files...');
        await execPromise('cp -r Koha dist/.');
        
        // Copy additional files if they exist
        const additionalFiles = ['tools', 'sample_data', 'README.md', 'LICENSE'];
        for (const file of additionalFiles) {
            try {
                if (fs.existsSync(file)) {
                    console.log(`Copying ${file}...`);
                    await execPromise(`cp -r ${file} dist/.`);
                }
            } catch (err) {
                console.warn(`Warning: Could not copy ${file}:`, err.message);
            }
        }
        
        // Update date in plugin file
        console.log('Updating plugin date...');
        await execPromise(`sed -i -e "s/1970-01-01/${today}/g" ${pm_file_path_full_dist}`);
        
        // Create KPZ archive
        console.log('Creating KPZ archive...');
        await execPromise(`cd dist && zip -r ../${release_filename} ./Koha ${additionalFiles.filter(f => fs.existsSync(f)).join(' ')}`);
        
        // Cleanup
        console.log('Cleaning up...');
        await execPromise('rm -rf dist');
        
        // Verify build
        if (fs.existsSync(release_filename)) {
            const stats = fs.statSync(release_filename);
            console.log(`✅ Build successful: ${release_filename} (${stats.size} bytes)`);
        } else {
            throw new Error('Build failed: KPZ file not created');
        }
        
        console.log('=== Build Complete ===');
        
    } catch (error) {
        console.error('❌ Build failed:', error.message);
        throw error;
    }
}

async function clean() {
    try {
        console.log('Cleaning build artifacts...');
        await execPromise('rm -f *.kpz');
        await execPromise('rm -rf dist');
        console.log('✅ Clean complete');
    } catch (error) {
        console.warn('Warning during clean:', error.message);
    }
}

async function verify() {
    try {
        console.log('=== Verifying Build ===');
        
        // Check if KPZ exists
        if (!fs.existsSync(release_filename)) {
            throw new Error(`KPZ file not found: ${release_filename}`);
        }
        
        // Check KPZ contents
        console.log('Checking KPZ contents...');
        const { stdout } = await execPromise(`unzip -l ${release_filename}`);
        console.log('KPZ contents:');
        console.log(stdout);
        
        // Verify main plugin file is included
        if (!stdout.includes('Koha/Plugin/Com/Theke/GOBI.pm')) {
            throw new Error('Main plugin file not found in KPZ');
        }
        
        console.log('✅ Verification complete');
        
    } catch (error) {
        console.error('❌ Verification failed:', error.message);
        throw error;
    }
}

// Export tasks
exports.static = static;
exports.build = series(static, build);
exports.clean = clean;
exports.verify = verify;
exports.default = series(clean, static, build, verify);

// Development task
exports.dev = series(clean, static, build);

// Release task
exports.release = series(clean, static, build, verify);
