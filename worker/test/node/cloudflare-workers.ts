// The node project has no Workers runtime, and its routes run with attestation off, so the
// Durable Object base class only has to exist for the import of src/index.ts.
export class DurableObject<E = unknown> {
  constructor(
    public ctx: DurableObjectState,
    public env: E,
  ) {}
}
