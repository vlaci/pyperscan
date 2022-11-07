use std::ffi::{c_int, c_void};
use std::ops::Deref;
use std::ptr;
use std::slice;

use pyo3::{ffi, prelude::*, AsPyPointer};

pub struct Buffer<'a>(&'a [u8]);

impl<'a> Deref for Buffer<'a> {
    type Target = [u8];

    fn deref(&self) -> &Self::Target {
        self.0
    }
}

impl<'a> FromPyObject<'a> for Buffer<'a> {
    fn extract(ob: &'a pyo3::PyAny) -> pyo3::PyResult<Self> {
        let mut buf = ptr::null::<u8>();
        let mut len = 0usize;
        let buf = unsafe {
            error_on_minus_one(
                ob.py(),
                PyObject_AsReadBuffer(
                    ob.as_ptr(),
                    &mut buf as *mut *const _ as *mut *const c_void,
                    &mut len as *mut _ as *mut isize,
                ),
            )?;
            slice::from_raw_parts(buf, len)
        };
        Ok(Buffer(buf))
    }
}

#[inline]
fn error_on_minus_one(py: Python, result: i32) -> PyResult<()> {
    if result == -1 {
        Err(PyErr::fetch(py))
    } else {
        Ok(())
    }
}

extern "C" {
    fn PyObject_AsReadBuffer(
        obj: *mut ffi::PyObject,
        buffer: *mut *const c_void,
        buffer_len: *mut ffi::Py_ssize_t,
    ) -> c_int;
}
