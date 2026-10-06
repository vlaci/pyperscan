use std::ops::Deref;
use std::sync::Mutex;

use super::Buffer;
use crate::hyperscan::{
    BlockDatabase, BlockScanner, Context, Error, Flag, HyperscanErrorCode, Pattern, Scan,
    StreamDatabase, StreamScanner, VectoredDatabase, VectoredScanner,
};
use pyo3::{create_exception, exceptions::PyValueError, prelude::*, types::PyTuple};

#[pyclass(name = "Pattern", module = "pyperscan._pyperscan", frozen)]
struct PyPattern {
    expression: Vec<u8>,
    tag: Option<Py<PyAny>>,
    flags: Flag,
}

#[allow(non_camel_case_types)]
#[allow(clippy::upper_case_acronyms)]
#[pyclass(eq, name = "Flag", from_py_object)]
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

#[pyclass(eq, name = "Scan", module = "pyperscan._pyperscan", from_py_object)]
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
        tag: Option<Py<PyAny>>,
    ) -> PyResult<Self> {
        let flags = flags
            .iter()
            .map(|f| f.extract::<PyFlag>().map_err(PyErr::from))
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

type TagMapping = Vec<Option<Py<PyAny>>>;

struct PyContext {
    user_data: Py<PyAny>,
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
        py: Python<'_>,
        user_data: Py<PyAny>,
        match_event_handler: Py<PyAny>,
    ) -> PyResult<PyBlockScanner> {
        let context = create_context(py, &self.tag_mapping, user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyBlockScanner(Mutex::new(scanner)))
    }
}

#[pyclass(name = "BlockScanner", module = "pyperscan._pyperscan")]
struct PyBlockScanner(Mutex<BlockScanner<PyContext>>);

#[pymethods]
impl PyBlockScanner {
    fn scan(&mut self, py: Python, data: Buffer) -> PyResult<PyScan> {
        let scanner = self
            .0
            .get_mut()
            .expect("mutex is never locked, it is used only to implement Sync");
        py.detach(|| Ok(scanner.scan(&data)?.into()))
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
        py: Python<'_>,
        user_data: Py<PyAny>,
        match_event_handler: Py<PyAny>,
    ) -> PyResult<PyVectoredScanner> {
        let context = create_context(py, &self.tag_mapping, user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyVectoredScanner(Mutex::new(scanner)))
    }
}

#[pyclass(name = "VectoredScanner", module = "pyperscan._pyperscan")]
struct PyVectoredScanner(Mutex<VectoredScanner<PyContext>>);

#[pymethods]
impl PyVectoredScanner {
    fn scan(&mut self, py: Python, data: Vec<Bound<'_, PyAny>>) -> PyResult<PyScan> {
        let data = data
            .iter()
            .map(|d| d.extract::<Buffer>())
            .collect::<PyResult<Vec<_>>>()?;
        let scanner = self
            .0
            .get_mut()
            .expect("mutex is never locked, it is used only to implement Sync");
        py.detach(|| {
            let data = data.iter().map(|d| d.deref()).collect();
            Ok(scanner.scan(data)?.into())
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
        py: Python<'_>,
        user_data: Py<PyAny>,
        match_event_handler: Py<PyAny>,
    ) -> PyResult<PyStreamScanner> {
        let context = create_context(py, &self.tag_mapping, user_data, match_event_handler)?;
        let scanner = self.db.create_scanner(context)?;
        Ok(PyStreamScanner(Mutex::new(scanner)))
    }
}

#[pyclass(name = "StreamScanner", module = "pyperscan._pyperscan")]
struct PyStreamScanner(Mutex<StreamScanner<PyContext>>);

#[pymethods]
impl PyStreamScanner {
    #[pyo3(signature = (data, chunk_size = None))]
    fn scan(&mut self, py: Python, data: Buffer, chunk_size: Option<usize>) -> PyResult<PyScan> {
        let scanner = self
            .0
            .get_mut()
            .expect("mutex is never locked, it is used only to implement Sync");
        py.detach(|| {
            let mut rv = Scan::default();
            match chunk_size {
                None => rv = scanner.scan(&data)?,
                Some(length) => {
                    for slice in data.chunks(length) {
                        rv = scanner.scan(slice)?;
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
        let scanner = self
            .0
            .get_mut()
            .expect("mutex is never locked, it is used only to implement Sync");
        Ok(scanner.reset()?.into())
    }
}

fn to_tag_mapping(
    py: Python<'_>,
    patterns: &Bound<'_, PyTuple>,
) -> PyResult<(Vec<Pattern>, TagMapping)> {
    Ok(patterns
        .into_iter()
        .map(|p| p.extract::<Py<PyPattern>>().map_err(PyErr::from))
        .collect::<PyResult<Vec<_>>>()?
        .iter()
        .enumerate()
        .map(move |(id, p)| {
            let pat = p.get();
            let tag = pat.tag.as_ref().map(|t| t.clone_ref(py));
            (
                Pattern::new(
                    pat.expression.clone(),
                    pat.flags,
                    Some(id.try_into().unwrap()),
                ),
                tag,
            )
        })
        //.collect::<PyResult<(Pattern, Option<Arc<Py<PyAny>>>)>>()?
        .unzip())
}

fn create_context(
    py: Python<'_>,
    tag_mapping: &TagMapping,
    user_data: Py<PyAny>,
    match_event_handler: Py<PyAny>,
) -> PyResult<Context<PyContext>> {
    let match_handler = move |ctx: &mut PyContext, id, from, to| -> Result<Scan, Error> {
        Python::attach(|py| -> PyResult<Scan> {
            let result;
            if let Some(id) = ctx.tag_mapping.get(id as usize).unwrap() {
                let args = (&ctx.user_data, id, from, to);
                result = match_event_handler.call1(py, args)?;
            } else {
                let args = (&ctx.user_data, id, from, to);
                result = match_event_handler.call1(py, args)?;
            }
            result
                .extract::<PyScan>(py)
                .map(Into::into)
                .map_err(PyErr::from)
        })
        .map_err(|exc| exc.into())
    };

    let tag_mapping = tag_mapping
        .iter()
        .map(|ot| ot.as_ref().map(|t| t.clone_ref(py)))
        .collect();
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
            Error::HyperscanCompile(msg, expr) => HyperscanCompileError::new_err((msg, expr)),
            Error::Python(exc) => exc,
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

#[pymodule(gil_used = false)]
fn _pyperscan(py: Python<'_>, m: &Bound<'_, PyModule>) -> PyResult<()> {
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
