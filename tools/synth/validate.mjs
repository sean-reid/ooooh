// Covers the JSON Schema keywords script.schema.json uses, nothing more.

const typeOf = (value) => {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (typeof value === "number")
    return Number.isInteger(value) ? "integer" : "number";
  return typeof value;
};

const matchesType = (value, type) => {
  const actual = typeOf(value);
  return type === actual || (type === "number" && actual === "integer");
};

export function validate(value, schema, path = "", errors = []) {
  if (schema.type) {
    const types = [].concat(schema.type);
    if (!types.some((type) => matchesType(value, type))) {
      errors.push(
        `${path || "/"}: expected ${types.join(" or ")}, got ${typeOf(value)}`,
      );
      return errors;
    }
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(
      `${path || "/"}: ${JSON.stringify(value)} is not one of ${schema.enum.join(", ")}`,
    );
  }
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${path}: shorter than ${schema.minLength} characters`);
    }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${path}: does not match ${schema.pattern}`);
    }
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path}: ${value} is below ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${path}: ${value} is above ${schema.maximum}`);
    }
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${path}: fewer than ${schema.minItems} items`);
    }
    if (schema.items) {
      value.forEach((item, index) =>
        validate(item, schema.items, `${path}/${index}`, errors),
      );
    }
  }
  if (typeOf(value) === "object") {
    for (const key of schema.required ?? []) {
      if (!(key in value)) errors.push(`${path || "/"}: missing ${key}`);
    }
    for (const [key, item] of Object.entries(value)) {
      const subschema = schema.properties?.[key];
      if (subschema) {
        validate(item, subschema, `${path}/${key}`, errors);
      } else if (schema.additionalProperties === false) {
        errors.push(`${path || "/"}: unknown property ${key}`);
      }
    }
  }
  return errors;
}
