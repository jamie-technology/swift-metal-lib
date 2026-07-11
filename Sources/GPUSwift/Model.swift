// The target-neutral description of a GPU kernel's interface.
//
// This is deliberately independent of Metal/AIR: it captures *intent* — which
// arguments are buffers in which address space, which are hardware builtins —
// so that a backend (AIR today, NVPTX/CUDA later) can lower it. The `smc`
// driver builds one of these per kernel (by inference from the emitted LLVM IR,
// or, once the compiler carries `@Compute`/`@Binding` attributes, directly from
// the frontend) and hands it to a backend to emit the ABI metadata.

/// GPU address spaces, matching the LLVM `addrspace(n)` numbering Apple's AIR uses.
public enum AddressSpace: Int, Sendable, Equatable {
    case function = 0     // thread-private / stack
    case device = 1       // `device`   — read/write global memory
    case constant = 2     // `constant` — read-only uniform memory
    case threadgroup = 3  // `threadgroup` — group-shared memory
}

/// How a buffer argument is accessed. Drives `air.read` / `air.read_write`.
public enum Access: String, Sendable, Equatable {
    case read           // `air.read`
    case write          // `air.write`
    case readWrite      // `air.read_write`
}

/// A scalar/vector element type carried by a buffer, used for reflection metadata
/// (`air.arg_type_name` / `air.arg_type_size`). Execution does not depend on it,
/// but validation tools and the Metal runtime surface it.
public struct DataType: Sendable, Equatable {
    public var airName: String   // e.g. "float", "uint", "float4"
    public var size: Int         // bytes
    public var align: Int        // bytes
    public init(airName: String, size: Int, align: Int) {
        self.airName = airName; self.size = size; self.align = align
    }
    public static let float = DataType(airName: "float", size: 4, align: 4)
    public static let uint  = DataType(airName: "uint",  size: 4, align: 4)
    public static let int   = DataType(airName: "int",   size: 4, align: 4)
}

/// A hardware-provided input, delivered as a trailing scalar parameter in AIR.
public enum Builtin: String, Sendable, Equatable {
    case threadPositionInGrid          = "air.thread_position_in_grid"
    case threadPositionInThreadgroup   = "air.thread_position_in_threadgroup"
    case threadgroupPositionInGrid     = "air.threadgroup_position_in_grid"
    case threadIndexInThreadgroup      = "air.thread_index_in_threadgroup"
    case threadgroupsPerGrid           = "air.threadgroups_per_grid"

    /// AIR reflects the scalar type name of a builtin (e.g. `uint`, `uint3`).
    public var argTypeName: String {
        switch self {
        case .threadIndexInThreadgroup: return "uint"
        default: return "uint"        // grid/threadgroup positions are uint for 1-D dispatch
        }
    }
}

/// One kernel argument: either a bound buffer or a hardware builtin.
public enum Argument: Sendable, Equatable {
    /// A pointer argument bound to a resource slot.
    case buffer(index: Int, space: AddressSpace, access: Access, element: DataType, name: String)
    /// A hardware-provided scalar input.
    case builtin(Builtin, name: String)

    public var name: String {
        switch self {
        case let .buffer(_, _, _, _, name): return name
        case let .builtin(_, name): return name
        }
    }
}

/// The kind of GPU entry point. Only compute is wired up today; the rest name
/// the AIR entry-point metadata list (`!air.vertex`, `!air.fragment`, …) they map to.
public enum Stage: String, Sendable {
    case compute  = "air.kernel"
    case vertex   = "air.vertex"
    case fragment = "air.fragment"
}

/// A complete, backend-neutral description of one kernel entry point.
public struct KernelInterface: Sendable {
    public var name: String
    public var stage: Stage
    public var arguments: [Argument]
    public init(name: String, stage: Stage = .compute, arguments: [Argument]) {
        self.name = name; self.stage = stage; self.arguments = arguments
    }
}
