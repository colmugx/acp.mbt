///|

///|
/// The Reader program produced by the Agent composition root.
pub type AgentProgram[Env] = @reader.Reader[
  Env,
  Result[@agent.AgentEndpoint, @acp_error.AgentCompositionError],
]

///|
/// Turn a caller-owned Reader of a validated service specification into a
/// one-shot endpoint program.  The Reader is still pure and synchronous; it
/// only captures the async callbacks in the endpoint value.
pub fn[Env] agent_program(
  spec_program : @reader.Reader[
    Env,
    Result[@agent.AgentSpec, @acp_error.AgentCompositionError],
  ],
) -> AgentProgram[Env] {
  @reader.Reader::map(spec_program, fn(result) {
    Result::map(result, fn(spec) { @agent.agent_endpoint_from_spec(spec) })
  })
}

///|
/// Convenience composition boundary for an arbitrary caller-owned Env.  The
/// projection is evaluated only when the returned Reader is run.
pub fn[Env] agent_program_from(
  project : (Env) -> Result[@agent.AgentSpec, @acp_error.AgentCompositionError],
) -> AgentProgram[Env] {
  agent_program(@reader.asks(project))
}
