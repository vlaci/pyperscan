use std::{ops::Deref, sync::Arc};

use super::Buffer;
use crate::hyperscan::{
    BlockDatabase, BlockScanner, Context, Error, Flag, HyperscanErrorCode, Pattern, Scan,
    StreamDatabase, StreamScanner, VectoredDatabase, VectoredScanner,
};
use pyo3::{
    create_exception, exceptions::PyValueError, prelude::*, types::PyTuple, IntoPyObjectExt,
};

#[pyclass(name = "Pattern", module = "pyperscan._pyperscan", unsendable)]
struct PyPattern {
    expression: Vec<u8>,
    tag: Option<PyObject>,
    flags: Flag,
}

#[allow(non_camel_case_types)]
#[allow(clippy::upper_case_acronyms)]
#[pyclass(eq, name = "Flag")]
#[derive(Clone, PartialEq)]
enum PyFlag {
    CASELESS,
    DOTALL,
    MULTILINE,
    SINGLEMATCH,
    ALLOWEMPTY,
    UTF8,
    UCP,
    PREFILTER,
    SOM_LEFTMOST,
    COMBINATION,
    QUIET,
}

#[pyclass(eq, name = "Scan", module = "pyperscan._pyperscan")]
#[derive(Clone, PartialEq)]
enum PyScan {
    Continue,
    Terminate,
}

impl From<Scan> for PyScan {
    fn from(s: Scan) -> Self {
        match s {
            Scan::Continue => Self::Continue,
            Scan::Terminate => Self::Terminate,
        }
    }
}

impl From<PyScan> for Scan {
    fn from(s: PyScan) -> Self {
        match s {
            PyScan::Continue => Self::Continue,
            PyScan::Terminate => Self::Terminate,
        }
    }
}

impl From<&PyFlag> for Flag {
    fn from(flags: &PyFlag) -> Self {
        match flags {
            PyFlag::CASELESS => Flag::CASELESS,
            PyFlag::DOTALL => Flag::DOTALL,
            PyFlag::MULTILINE => Flag::MULTILINE,
            PyFlag::SINGLEMATCH => Flag::SINGLEMATCH,
            PyFlag::ALLOWEMPTY => Flag::ALLOWEMPTY,
            PyFlag::UTF8 => Flag::UTF8,
            PyFlag::UCP => Flag::UCP,
            PyFlag::PREFILTER => Flag::PREFILTER,
            PyFlag::SOM_LEFTMOST => Flag::SOM_LEFTMOST,
            PyFlag::COMBINATION => Flag::COMBINATION,
            PyFlag::QUIET => Flag::QUIET,
        }
    }
}

#[pymethods]
impl PyPattern {
    #[new]
    #[pyo3(signature = (expression, *flags, tag = None))]
    fn py_new(
        expression: &'_ [u8],
        flags: &Bound<'_, PyTuple>,
        tag: Option<PyObject>,
    ) -> PyResult<Self> {
        let flags = flags
            .iter()
            .map(|f| f.extract::<PyFlag>())
            .collect::<PyResult<Vec<_>>>()?
            .iter()
            .fold(Flag::empty(), |a, f| a.union(f.into()));
        Ok(PyPattern {
            expression: expression.into(),
            tag,
            flags,
        })
    }
}

type TagMapping = Vec<Option<Arc<PyObject>>>;

struct PyContext {
    user_data: PyObject,
    tag_mapping: TagMapping,
}

#[pyclass(name = "BlockDatabase", module = "pyperscan._pyperscan")]
struct PyBlockDatabase {
    db: BlockDatabase,
    tag_mapping: TagMapping,
}

#[pymethods]
impl PyBlockDatabase {
    #[new]
    #[pyo3(signature = (*patterns))]
    fn py_new(py: Python<'_>, patterns: &Bound<'_, PyTuple>) -> PyResult<Self> {
        let (patterns, tag_mapping) = to_tag_mapping(py, patterns)?;
        Ok(Self {
            db: BlockDatabase::new(patterns)?,
            tag_mapping,
        })
    }

    fn build(
        &self,
        user_data: PyObject,
        match_event_handler: PyObject,
    ) -> PyResult<PyBlockScanner> {
        let context = create_context(self.tag_mapping.clone(), user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyBlockScanner(scanner))
    }
}

#[pyclass(unsendable, name = "BlockScanner", module = "pyperscan._pyperscan")]
struct PyBlockScanner(BlockScanner<PyContext>);

#[pymethods]
impl PyBlockScanner {
    fn scan(&mut self, py: Python, data: Buffer) -> PyResult<PyScan> {
        py.allow_threads(|| Ok(self.0.scan(&data)?.into()))
    }
}

#[pyclass(name = "VectoredDatabase", module = "pyperscan._pyperscan")]
struct PyVectoredDatabase {
    db: VectoredDatabase,
    tag_mapping: TagMapping,
}

#[pymethods]
impl PyVectoredDatabase {
    #[new]
    #[pyo3(signature = (*patterns))]
    fn py_new(py: Python<'_>, patterns: &Bound<'_, PyTuple>) -> PyResult<Self> {
        let (patterns, tag_mapping) = to_tag_mapping(py, patterns)?;
        Ok(Self {
            db: VectoredDatabase::new(patterns)?,
            tag_mapping,
        })
    }

    fn build(
        &self,
        user_data: PyObject,
        match_event_handler: PyObject,
    ) -> PyResult<PyVectoredScanner> {
        let context = create_context(self.tag_mapping.clone(), user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyVectoredScanner(scanner))
    }
}

#[pyclass(unsendable, name = "VectoredScanner", module = "pyperscan._pyperscan")]
struct PyVectoredScanner(VectoredScanner<PyContext>);

#[pymethods]
impl PyVectoredScanner {
    fn scan(&mut self, py: Python, data: Vec<Buffer>) -> PyResult<PyScan> {
        py.allow_threads(|| {
            let data = data.iter().map(|d| d.deref()).collect();
            Ok(self.0.scan(data)?.into())
        })
    }
}
#[pyclass(name = "StreamDatabase", module = "pyperscan._pyperscan")]
struct PyStreamDatabase {
    db: StreamDatabase,
    tag_mapping: TagMapping,
}

#[pymethods]
impl PyStreamDatabase {
    #[new]
    #[pyo3(signature=(*patterns))]
    fn py_new(py: Python<'_>, patterns: &Bound<'_, PyTuple>) -> PyResult<Self> {
        let (patterns, tag_mapping) = to_tag_mapping(py, patterns)?;
        Ok(Self {
            db: StreamDatabase::new(patterns)?,
            tag_mapping,
        })
    }

    fn build(
        &self,
        user_data: PyObject,
        match_event_handler: PyObject,
    ) -> PyResult<PyStreamScanner> {
        let context = create_context(self.tag_mapping.clone(), user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyStreamScanner(scanner))
    }
}

#[pyclass(name = "StreamScanner", module = "pyperscan._pyperscan", unsendable)]
struct PyStreamScanner(StreamScanner<PyContext>);

#[pymethods]
impl PyStreamScanner {
    #[pyo3(signature = (data, chunk_size = None))]
    fn scan(&mut self, py: Python, data: Buffer, chunk_size: Option<usize>) -> PyResult<PyScan> {
        py.allow_threads(|| {
            let mut rv = Scan::default();
            match chunk_size {
                None => rv = self.0.scan(&data)?,
                Some(length) => {
                    for slice in data.chunks(length) {
                        rv = self.0.scan(slice)?;
                        if rv == Scan::Terminate {
                            break;
                        }
                    }
                }
            };

            Ok(rv.into())
        })
    }

    fn reset(&mut self) -> PyResult<PyScan> {
        Ok(self.0.reset()?.into())
    }
}

fn to_tag_mapping(
    py: Python<'_>,
    patterns: &Bound<'_, PyTuple>,
) -> PyResult<(Vec<Pattern>, TagMapping)> {
    Ok(patterns
        .into_iter()
        .map(|p| p.extract::<Py<PyPattern>>())
        .collect::<PyResult<Vec<_>>>()?
        .iter()
        .enumerate()
        .map(move |(id, p)| {
            let pat = p.borrow_mut(py);
            let tag = pat
                .tag
                .as_ref()
                .map(|t| Arc::new(t.into_py_any(py).unwrap()));
            (
                Pattern::new(
                    pat.expression.clone(),
                    pat.flags,
                    Some(id.try_into().unwrap()),
                ),
                tag,
            )
        })
        //.collect::<PyResult<(Pattern, Option<Arc<PyObject>>)>>()?
        .unzip())
}

fn create_context(
    tag_mapping: TagMapping,
    user_data: PyObject,
    match_event_handler: PyObject,
) -> PyResult<Context<PyContext>> {
    let match_handler = move |ctx: &mut PyContext, id, from, to| -> Result<Scan, Error> {
        Python::with_gil(|py| {
            let result;
            if let Some(id) = ctx.tag_mapping.get(id as usize).unwrap() {
                let args = (&ctx.user_data, id.deref(), from, to);
                result = match_event_handler.call1(py, args)?;
            } else {
                let args = (&ctx.user_data, id, from, to);
                result = match_event_handler.call1(py, args)?;
            }
            result.extract::<PyScan>(py).map(|s| s.into())
        })
        .map_err(|exc| exc.into())
    };
    let py_user_data = PyContext {
        user_data,
        tag_mapping,
    };
    Ok(Context::new(py_user_data, match_handler))
}

impl From<Error> for PyErr {
    fn from(err: Error) -> PyErr {
        match err {
            Error::Nul(_) => PyValueError::new_err(format!("{err}")),
            Error::Hyperscan(e, c) => HyperscanError::new_err((e, c)),
            Error::HypercanCompile(msg, expr) => HyperscanCompileError::new_err((msg, expr)),
            Error::PythonError(exc) => exc,
        }
    }
}

create_exception!(
    pyperscan._pyperscan,
    HyperscanError,
    pyo3::exceptions::PyException
);
create_exception!(
    pyperscan._pyperscan,
    HyperscanCompileError,
    pyo3::exceptions::PyException
);

#[pymodule]
pub fn _pyperscan(py: Python<'_>, m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<PyFlag>()?;
    m.add_class::<PyScan>()?;
    m.add_class::<PyBlockDatabase>()?;
    m.add_class::<PyBlockScanner>()?;
    m.add_class::<PyVectoredDatabase>()?;
    m.add_class::<PyVectoredScanner>()?;
    m.add_class::<PyStreamDatabase>()?;
    m.add_class::<PyStreamScanner>()?;
    m.add_class::<PyPattern>()?;
    m.add_class::<HyperscanErrorCode>()?;

    m.add("HyperscanError", py.get_type::<HyperscanError>())?;
    m.add(
        "HyperscanCompileError",
        py.get_type::<HyperscanCompileError>(),
    )?;
    Ok(())
}
