#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
function load(file) {
    const context = {};
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../..', file), 'utf8').replace(/\.pragma library/g, ''), context);
    return context;
}
const styles = load('modules/theme/ShellStyles.js');
const defaults = load('config/defaults/theme.js').data;
const validator = load('config/ConfigValidator.js');
assert.strictEqual(defaults.shellStyle, 'glass');
assert.strictEqual(defaults.ditherTintColor, '#4c9cbd');
for (const id of ['original','teal-orange','tint']) assert.strictEqual(validator.validate(id,'original','ditherPalette'),id);
assert.strictEqual(validator.validate('#Ff00Aa',defaults.ditherTintColor,'ditherTintColor'),'#ff00aa');
for (const bad of ['red','#abcd','#12zz00','#11223344']) assert.strictEqual(validator.validate(bad,defaults.ditherTintColor,'ditherTintColor'),defaults.ditherTintColor);

assert.strictEqual(defaults.ditherBorder,'band');
assert.strictEqual(defaults.wallpaperDitherStrength,'strong');
for (const id of ['band','double','dotted']) assert.strictEqual(validator.validate(id,'band','ditherBorder'),id);
for (const id of ['normal','strong','intense']) assert.strictEqual(validator.validate(id,'strong','wallpaperDitherStrength'),id);
assert.strictEqual(validator.validate('broken','double','ditherBorder'),'double');
assert.strictEqual(validator.validate('broken','strong','wallpaperDitherStrength'),'strong');
for (const id of ['glass', 'quiet', 'colorful', 'dithered', 'custom']) {
    assert.strictEqual(validator.validate(id, 'glass', 'shellStyle'), id);
}
assert.strictEqual(validator.validate('broken', 'glass', 'shellStyle'), 'glass');
const migrated = validator.validate({shellStyle: 'quiet', roundness: 12}, defaults, 'theme');
assert.strictEqual(migrated.shellStyle, 'quiet');
assert.strictEqual(migrated.roundness, 12);
function luminance(hex) {
    const c = hex.slice(-6).match(/../g).map(x => parseInt(x, 16) / 255).map(x => x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4);
    return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}
const palettes = [
    {background:'#13100e',foreground:'#f3dfd3',primary:'#ffb68c',onPrimary:'#502500',secondary:'#e5bea8',onSecondary:'#432b1d',tertiary:'#c8cb95',onTertiary:'#30330d',error:'#ffb4ab',onError:'#690005'},
    {background:'#fff8f5',foreground:'#241a15',primary:'#825430',onPrimary:'#ffffff',secondary:'#795844',onSecondary:'#ffffff',tertiary:'#626431',onTertiary:'#ffffff',error:'#ba1a1a',onError:'#ffffff'}
];
let count = 0;
for (const style of ['glass', 'quiet', 'colorful', 'dithered']) {
    for (const palette of palettes) {
        for (const role of ['bg','popup','pane','surface','common','internalbg','focus','primary','secondary','tertiary','error']) {
            const config = styles.surface(style, role, palette);
            const fill = config.gradient[0][0];
            assert.match(fill, /^#[0-9a-f]{6}$/i);
            assert(config.opacity > 0 && config.opacity <= 1);
            if (style === 'quiet') assert.strictEqual(config.opacity, 1);
            if (style === 'dithered') {
                assert.strictEqual(config.opacity, 1);
                if (['bg','popup','pane','surface','common','internalbg','focus'].includes(role)) {
                    assert.strictEqual(config.gradientType, 'halftone');
                    const a = luminance(config.halftoneDotColor), b = luminance(config.itemColor);
                    assert((Math.max(a,b) + 0.05) / (Math.min(a,b) + 0.05) >= 4.5, `${style}/${role} dot text contrast`);
                }
            }
            const a = luminance(fill), b = luminance(config.itemColor);
            assert((Math.max(a,b) + 0.05) / (Math.min(a,b) + 0.05) >= 4.5, `${style}/${role} text contrast`);
            count++;
        }
    }
}
assert.strictEqual(defaults.ditherStrength, 20);
assert.strictEqual(validator.validate(-10,20,'ditherStrength'),0);
assert.strictEqual(validator.validate(150,20,'ditherStrength'),100);
assert.strictEqual(validator.validate(NaN,20,'ditherStrength'),20);
assert.strictEqual(validator.validate(37.7,20,'ditherStrength'),38);
for (const strength of [0,20,50,75,100]) {
    for (const palette of palettes) {
        for (const role of ['bg','popup','pane','common','internalbg','focus','primary','primaryfocus','overprimary','secondary','tertiary','error']) {
            const config = styles.surface('dithered',role,palette,strength);
            if (strength === 0) assert.strictEqual(config.gradientType,'linear');
            else if (strength > 20 || ['bg','popup','pane','common','internalbg','focus'].includes(role)) {
                assert.strictEqual(config.gradientType,'halftone');
                assert(styles.contrast(config.halftoneDotColor,config.itemColor) >= 4.5, `${strength}/${role} dot contrast`);
                count++;
            }
        }
    }
}
const subtle=styles.surface('dithered','bg',palettes[0],20);
assert.strictEqual(subtle.halftoneDotMax,1.4);
assert.strictEqual(subtle.halftoneDotColor,styles.mix(subtle.gradient[0][0],palettes[0].foreground,0.02));
const bold=styles.surface('dithered','bg',palettes[0],100);
assert(bold.halftoneDotMax>subtle.halftoneDotMax);
assert.notStrictEqual(bold.halftoneDotColor,subtle.halftoneDotColor);
assert.strictEqual(styles.surface('dithered','transparent',palettes[0],100).opacity,0);
for (const role of ['bar','barbg']) {
    for (const strength of [20,75,100]) {
        for (const palette of palettes) {
            const config=styles.surface('dithered',role,palette,strength);
            assert.strictEqual(config.opacity,1);
            assert.strictEqual(config.gradientType,'halftone');
            assert.strictEqual(config.border[1],1);
            assert(config.halftoneDotMin/config.halftoneDotMax >= 0.7);
            assert.strictEqual(config.halftoneDotMin,config.halftoneDotMax);
            assert.strictEqual(config.halftoneDotMax,styles.ditherCellSize(strength));
            assert.strictEqual(config.gradientAngle,0);
            assert(styles.contrast(config.halftoneDotColor,config.itemColor) >= 4.5);
            count++;
        }
    }
}
for (const style of ['glass','quiet','colorful']) {
    assert.strictEqual(styles.surface(style,'barbg',palettes[0],100).opacity,0);
}
assert.strictEqual(styles.surface('dithered','barbg',palettes[0],0).opacity,0);
for (const strength of [1,20,50,75,100]) {
    const reference=styles.ditherCellSize(strength);
    for (const role of ['bg','popup','pane','common','internalbg','focus','bar','barbg','primary']) {
        const config=styles.surface('dithered',role,palettes[0],strength);
        if (config.gradientType==='halftone') {
            assert.strictEqual(config.halftoneDotMin,reference);
            assert.strictEqual(config.halftoneDotMax,reference);
        }
    }
}
console.log(`Shell style schema, migration and ${count} surface contrast checks passed.`);
