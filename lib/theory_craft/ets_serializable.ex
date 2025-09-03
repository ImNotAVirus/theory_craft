defmodule TheoryCraft.ETSSerializable do
  @moduledoc """
  Behaviour for ETS serializable structs.
  """

  @callback to_tuple(struct :: struct(), precision :: :native | System.time_unit()) :: tuple()
  @callback from_tuple(tuple(), precision :: :native | System.time_unit()) :: struct()
end
