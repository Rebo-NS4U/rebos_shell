.pragma library

function fields(schema) {
    let properties = schema && schema.properties ? schema.properties : {};
    // QML list<var> exposes nested JSON arrays as array-like QVariantLists.
    let required = schema && schema.required ? Array.from(schema.required) : [];
    return Object.keys(properties).map(key => {
        let field = properties[key];
        let source = field.type === "array" ? (field.items || {}) : field;
        let choices = source.oneOf || source.anyOf || [];
        if (source.enum)
            choices = Array.from(source.enum).map(value => ({const: value, title: value}));
        return {
            key: key,
            title: field.title || key,
            description: field.description || "",
            type: field.type || "string",
            required: required.includes(key),
            secret: !!(field._meta && field._meta.codex && field._meta.codex.isSecret),
            choices: choices.map(option => ({value: option.const, label: option.title || String(option.const), description: option.description || ""})),
            schema: field
        };
    });
}

function validate(schema, draft) {
    let content = {};
    for (let field of fields(schema)) {
        let value = draft[field.key];
        let rules = field.schema;
        let empty = value === undefined || value === null || (typeof value === "string" && !value.trim());
        if (empty) {
            if (field.required)
                return {error: "Answer “" + field.title + "” before sending."};
            continue;
        }
        if (field.type === "number" || field.type === "integer") {
            value = Number(value);
            if (!Number.isFinite(value) || (field.type === "integer" && !Number.isInteger(value)))
                return {error: "Enter a valid " + field.type + " for “" + field.title + "”."};
            if ((rules.minimum != null && value < rules.minimum) || (rules.maximum != null && value > rules.maximum))
                return {error: "The answer to “" + field.title + "” is outside the allowed range."};
        } else if (field.type === "boolean") {
            if (typeof value !== "boolean")
                return {error: "Choose Yes or No for “" + field.title + "”."};
        } else if (field.type === "array") {
            if (!Array.isArray(value) || value.some(item => typeof item !== "string"))
                return {error: "Choose values for “" + field.title + "”."};
            if ((field.required && value.length === 0) || (rules.minItems != null && value.length < rules.minItems) || (rules.maxItems != null && value.length > rules.maxItems))
                return {error: "Check the number of choices for “" + field.title + "”."};
            if (field.choices.length && value.some(item => !field.choices.some(choice => choice.value === item)))
                return {error: "Choose one of the listed answers for “" + field.title + "”."};
        } else if (field.type === "string") {
            value = String(value);
            if ((rules.minLength != null && value.length < rules.minLength) || (rules.maxLength != null && value.length > rules.maxLength))
                return {error: "Check the length of “" + field.title + "”."};
            let formatValid = true;
            if (rules.format === "email")
                formatValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
            else if (rules.format === "uri")
                formatValid = /^[a-z][a-z0-9+.-]*:\S+$/i.test(value);
            else if (rules.format === "date") {
                let date = new Date(value);
                formatValid = /^\d{4}-\d{2}-\d{2}$/.test(value) && !isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
            } else if (rules.format === "date-time") {
                formatValid = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/i.test(value) && !isNaN(Date.parse(value));
            }
            if (!formatValid)
                return {error: "Enter a valid " + rules.format + " for “" + field.title + "”."};
            if (rules.pattern) {
                try {
                    if (!(new RegExp(rules.pattern)).test(value))
                        return {error: "The answer to “" + field.title + "” does not match the requested format."};
                } catch (e) {
                    return {error: "This question has an invalid format rule."};
                }
            }
            if (field.choices.length && !field.choices.some(choice => choice.value === value))
                return {error: "Choose one of the listed answers for “" + field.title + "”."};
        } else {
            return {error: "Unsupported question field: " + field.type};
        }
        content[field.key] = value;
    }
    return {content: content};
}
