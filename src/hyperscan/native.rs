use foreign_types::ForeignType;
use hyperscan_sys as hs;
use std::ffi::c_void;

use super::{wrapper, AsResult, Error, HyperscanErrorCode, Pattern, ScanMode};

#[derive(Default, Eq, PartialEq)]
pub enum Scan {
    #[default]
    Continue,
    Terminate,
}

pub trait MatchEventHandler<T>: Fn(&mut T, u32, u64, u64) -> Result<Scan, Error> {}

impl<T, F: Fn(&mut T, u32, u64, u64) -> Result<Scan, Error>> MatchEventHandler<T> for F {}

pub struct BlockDatabase {
    db: wrapper::Database,
}

pub struct BlockScanner<U> {
    scratch: wrapper::Scratch,
    database: wrapper::Database,
    context: Context<U>,
}

impl BlockDatabase {
    pub fn new(patterns: Vec<Pattern>) -> Result<Self, Error> {
        let db = wrapper::Database::new(patterns, ScanMode::BLOCK)?;
        Ok(Self { db })
    }

    pub fn create_scanner<U: 'static>(
        &self,
        context: Context<U>,
    ) -> Result<BlockScanner<U>, Error> {
        BlockScanner::new(self, context)
    }
}

pub struct VectoredDatabase {
    db: wrapper::Database,
}

pub struct VectoredScanner<U> {
    scratch: wrapper::Scratch,
    database: wrapper::Database,
    context: Context<U>,
}

impl VectoredDatabase {
    pub fn new(patterns: Vec<Pattern>) -> Result<Self, Error> {
        let db = wrapper::Database::new(patterns, ScanMode::VECTORED)?;
        Ok(Self { db })
    }

    pub fn create_scanner<U: 'static>(
        &self,
        context: Context<U>,
    ) -> Result<VectoredScanner<U>, Error> {
        VectoredScanner::new(self, context)
    }
}

pub struct StreamDatabase {
    db: wrapper::Database,
}

pub struct StreamScanner<U> {
    scratch: wrapper::Scratch,
    stream: wrapper::Stream,
    context: Context<U>,
}

impl StreamDatabase {
    pub fn new(patterns: Vec<Pattern>) -> Result<Self, Error> {
        let db = wrapper::Database::new(patterns, ScanMode::STREAM | ScanMode::SOM_LARGE)?;
        Ok(Self { db })
    }

    pub fn create_scanner<U: 'static>(
        &self,
        context: Context<U>,
    ) -> Result<StreamScanner<U>, Error> {
        StreamScanner::new(self, context)
    }
}

pub struct Context<U> {
    user_data: U,
    match_error: Option<Error>,
    match_event_handler: Box<dyn MatchEventHandler<U> + Send>,
}

impl<U> Context<U> {
    pub fn new(
        user_data: U,
        match_event_handler: impl MatchEventHandler<U> + Send + 'static,
    ) -> Self {
        Self {
            user_data,
            match_error: None,
            match_event_handler: Box::new(match_event_handler),
        }
    }
}

impl<U> BlockScanner<U> {
    pub fn new(db: &BlockDatabase, context: Context<U>) -> Result<Self, Error> {
        let scratch = wrapper::Scratch::new(&db.db)?;

        Ok(Self {
            database: db.db.try_clone()?,
            scratch,
            context,
        })
    }
}

impl<U> VectoredScanner<U> {
    pub fn new(db: &VectoredDatabase, context: Context<U>) -> Result<Self, Error> {
        let scratch = wrapper::Scratch::new(&db.db)?;

        Ok(Self {
            database: db.db.try_clone()?,
            scratch,
            context,
        })
    }
}

impl<U> StreamScanner<U> {
    pub fn new(db: &StreamDatabase, context: Context<U>) -> Result<Self, Error> {
        let scratch = wrapper::Scratch::new(&db.db)?;
        let stream = wrapper::Stream::new(&db.db)?;

        Ok(Self {
            scratch,
            stream,
            context,
        })
    }
}

impl<U> StreamScanner<U> {
    pub fn scan(&mut self, data: &[u8]) -> Result<Scan, Error> {
        unsafe {
            hs::hs_scan_stream(
                self.stream.as_ptr(),
                data.as_ptr() as *const _,
                data.len() as u32,
                0,
                self.scratch.as_ptr(),
                Some(on_match::<U>),
                &mut self.context as *mut _ as *mut c_void,
            )
            .ok()
            .to_scan_result(self.context.match_error.take())
        }
    }

    pub fn reset(&mut self) -> Result<Scan, Error> {
        unsafe {
            hs::hs_reset_stream(
                self.stream.as_ptr(),
                0,
                self.scratch.as_ptr(),
                Some(on_match::<U>),
                &mut self.context as *mut _ as *mut c_void,
            )
            .ok()
            .to_scan_result(self.context.match_error.take())
        }
    }
}

impl<U> BlockScanner<U> {
    pub fn scan(&mut self, data: &[u8]) -> Result<Scan, Error> {
        unsafe {
            hs::hs_scan(
                self.database.as_ptr(),
                data.as_ptr() as *const _,
                data.len() as u32,
                0,
                self.scratch.as_ptr(),
                Some(on_match::<U>),
                &mut self.context as *mut _ as *mut c_void,
            )
            .ok()
            .to_scan_result(self.context.match_error.take())
        }
    }
}

impl<U> VectoredScanner<U> {
    pub fn scan(&mut self, data: Vec<&[u8]>) -> Result<Scan, Error> {
        let (len, data): (Vec<_>, Vec<_>) =
            data.iter().map(|d| (d.len() as u32, d.as_ptr())).unzip();
        unsafe {
            hs::hs_scan_vector(
                self.database.as_ptr(),
                data.as_ptr() as *const *const _,
                len.as_ptr(),
                len.len() as u32,
                0,
                self.scratch.as_ptr(),
                Some(on_match::<U>),
                &mut self.context as *mut _ as *mut c_void,
            )
            .ok()
            .to_scan_result(self.context.match_error.take())
        }
    }
}

trait ScanResult: Sized {
    fn to_scan_result(self, inner_err: Option<Error>) -> Result<Scan, Error>;
}

impl ScanResult for Result<(), Error> {
    fn to_scan_result(self, inner_err: Option<Error>) -> Result<Scan, Error> {
        if let Some(inner) = inner_err {
            Err(inner)
        } else {
            match self {
                Ok(_) => Ok(Scan::Continue),
                Err(err) => match err {
                    Error::Hyperscan(HyperscanErrorCode::ScanTerminated, _) => Ok(Scan::Terminate),
                    err => Err(err),
                },
            }
        }
    }
}

unsafe extern "C" fn on_match<U>(
    id: u32,
    from: u64,
    to: u64,
    _flags: u32,
    ctx: *mut c_void,
) -> i32 {
    let context = (ctx as *mut Context<U>)
        .as_mut()
        .expect("Context object unset");
    (context.match_event_handler)(&mut context.user_data, id, from, to).map_or_else(
        |err| {
            context.match_error = Some(err);
            -1
        },
        |rv| match rv {
            Scan::Continue => 0,
            Scan::Terminate => 1,
        },
    )
}
