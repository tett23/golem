//! The guest side of Golem's plugin ABI (golem-plugin ADR 0001,
//! docs/adr/0105, docs/adr/0106): CBOR, the semantic IR, the requests
//! and responses, and the exports a plugin module needs.
//!
//! A plugin is a `cdylib` for `wasm32-unknown-unknown` that defines two
//! functions and exports them with [`export_plugin!`]:
//!
//! ```ignore
//! use golem_plugin_sdk::*;
//!
//! fn describe() -> Description {
//!     Description { commands: vec!["hello".into()], ..Default::default() }
//! }
//!
//! fn invoke(req: Request) -> Response {
//!     match req {
//!         Request::Command(c) => Response::inlines(vec![Inline::Text { span: c.span, text: "hello".into() }]),
//!         Request::Filter(f) => Response::document(f.document),
//!     }
//! }
//!
//! export_plugin!(describe, invoke);
//! ```
//!
//! The host gives each call a fresh instance, so nothing is freed: the
//! request and the response live until the instance is dropped.

pub mod cbor;
pub mod ir;
pub mod protocol;

pub use cbor::Value;
pub use ir::{Block, BlockBody, DefGroup, Document, Inline, ListItem, NumberStyle, RefKind, RubySegment, Sp, Span, ABI_VERSION};
pub use protocol::{
    Arg, ArgValue, ChannelDecl, ChannelOrder, CommandRequest, Data, Description, Diagnostic, FilterRequest, Output, Request, Response,
    Severity,
};

/// The host side of the exports; [`export_plugin!`] calls these.
pub mod abi {
    use super::*;

    fn leak(bytes: Vec<u8>) -> u64 {
        let b = bytes.into_boxed_slice();
        let len = b.len() as u64;
        let ptr = Box::leak(b).as_ptr() as usize as u64;
        (ptr << 32) | len
    }

    /// `golem_alloc`: a region of `len` bytes the host writes the request into.
    pub fn alloc(len: u32) -> u32 {
        let b = vec![0u8; len as usize].into_boxed_slice();
        Box::leak(b).as_mut_ptr() as usize as u32
    }

    /// `golem_describe`: the description as CBOR, position and length packed.
    pub fn describe(f: fn() -> Description) -> u64 {
        leak(cbor::encode(&protocol::description_value(&f())))
    }

    /// `golem_invoke`. A request that does not decode is a bug of the host or
    /// of this crate; it traps, which the host reports as G06009.
    pub fn invoke(ptr: u32, len: u32, f: fn(Request) -> Response) -> u64 {
        // SAFETY: the host wrote `len` bytes at `ptr`, a region golem_alloc returned
        let input = unsafe { core::slice::from_raw_parts(ptr as usize as *const u8, len as usize) };
        let req = match cbor::decode(input).and_then(|v| protocol::request_of(&v)) {
            Ok(r) => r,
            Err(e) => panic!("golem-plugin-sdk: bad request: {e}"),
        };
        leak(cbor::encode(&protocol::response_value(&f(req))))
    }
}

/// Exports `golem_abi_version`, `golem_alloc`, `golem_describe` and
/// `golem_invoke` from a description function and an invoke function.
#[macro_export]
macro_rules! export_plugin {
    ($describe:path, $invoke:path) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn golem_abi_version() -> u32 {
            $crate::ABI_VERSION
        }
        #[unsafe(no_mangle)]
        pub extern "C" fn golem_alloc(len: u32) -> u32 {
            $crate::abi::alloc(len)
        }
        #[unsafe(no_mangle)]
        pub extern "C" fn golem_describe() -> u64 {
            $crate::abi::describe($describe)
        }
        #[unsafe(no_mangle)]
        pub extern "C" fn golem_invoke(ptr: u32, len: u32) -> u64 {
            $crate::abi::invoke(ptr, len, $invoke)
        }
    };
}
