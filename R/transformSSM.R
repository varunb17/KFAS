#' Transform the SSModel object with multivariate observations
#'
#' Function transform.SSModel transforms original model by LDL decomposition or state vector augmentation,
#'
#' @details As all the functions in KFAS use univariate approach, \eqn{H_t}{H[t]}, a covariance matrix of
#' an observation equation needs to be either diagonal or zero matrix. Function transformSSM performs
#' either the LDL decomposition of the covariance matrix of the observation equation, or augments the state vector with
#' the disturbances of the observation equation.
#'
#' In case of a LDL decomposition, the new \eqn{H_t}{H[t]} contains the diagonal part of the decomposition,
#' whereas observations \eqn{y_t}{Z[t]} and system matrices \eqn{Z_t}{Z[t]} are multiplied with the inverse of \eqn{L_t}{L[t]}.
#'
#'
#' @useDynLib KFAS ldlssm
#' @export
#' @param object State space model object from function SSModel.
#' @param type Option \code{"ldl"} performs LDL decomposition for covariance
#' matrix \eqn{H_t}{H[t]}, and multiplies the observation equation with the \eqn{L_t^{-1}}{L[t]^-1}, so
#' \eqn{\epsilon_t^* \sim N(0,D_t)}{\epsilon[t]* ~ N(0,D[t])}. Option \code{"augment"} adds \eqn{\epsilon_t}{\epsilon[t]} to the state vector, when
#' \eqn{Q_t}{Q[t]} becomes block diagonal with blocks \eqn{Q_t}{Q[t]} and \eqn{H_t}{H[t]}.
#' In case of univariate series, option \code{"ldl"} only changes the \code{H_type} argument of the model to \code{"Diagonal"}.
#' @return \item{model}{Transformed model.}
transformSSM <- function(object, type = c("ldl", "augment")) {
    if(object$distribution!="Gaussian")
        stop("Nothing to transform as matrix H is not defined for non-Gaussian model.")
    
    type <- match.arg(type, choices = c("ldl", "augment"))
    
    p <- object$p
    n <- object$n
    m <- object$m
    r <- object$k
    
    tv <- array(0, dim = 5)
    tv[1] <- dim(object$Z)[3] > 1
    tv[2] <- tvh <- dim(object$H)[3] > 1
    tv[3] <- dim(object$T)[3] > 1
    tv[4] <- dim(object$R)[3] > 1
    tv[5] <- dim(object$Q)[3] > 1
    
    
    
    if (type == "ldl") {
        if (p > 1) { 
            yt <- t(object$y)
            ymiss <- is.na(yt)
            tv[1] <- max(tv[1], tv[2])
            if (sum(ymiss) > 0) {
                positions <- unique(ymiss, MARGIN = 2)
                nh <- dim(positions)[2]
                tv[1:2] <- 1
                Z <- array(object$Z, dim = c(p, m, n))
            } else {
                Z <- array(object$Z, dim = c(p, m, (n - 1) * tv[1] + 1))
                positions <- rep(FALSE, p)
                nh <- 1
            }
            positions <- as.matrix(positions)
            H <- array(object$H, c(p, p, n))
            if (tvh) {
                nh <- n
                hchol <- 1:n
                uniqs <- 1:n
            } else {
                hchol <- rep(0, n)
                uniqs <- numeric(nh)
                for (i in 1:nh) {
                    nhn <- which(colSums(ymiss == positions[, i]) == p)
                    hchol[nhn] <- i
                    uniqs[i] <- nhn[1]  #which(hchol==i)[1]
                }
            }
            
            ichols <- H[, , uniqs, drop = FALSE]  #array(p,p,nh) #.Fortran('ldlinv2', PACKAGE = 'KFAS', NAOK = TRUE, H=H[,,uniqs],p,as.integer(ydimt[uniqs]),nh)$H
            
            ydims <- as.integer(colSums(!ymiss))
            yobs <- array(1:p, c(p, n))
            if (sum(ymiss) > 0) 
                for (i in 1:n) {
                    if (ydims[i] != p && ydims[i] != 0) 
                        yobs[1:ydims[i], i] <- yobs[!ymiss[, i], i]
                    if (ydims[i] < p) 
                        yobs[(ydims[i] + 1):p, i] <- NA
                }
            
            
            unidim <- ydims[uniqs]
            hobs <- yobs[, uniqs, drop = FALSE]
            storage.mode(yobs)<-storage.mode(hobs)<-storage.mode(hchol)<-"integer"
            out <- .Fortran("ldlssm", NAOK = TRUE, yt = yt, ydims = ydims, yobs = yobs, 
                    tv = as.integer(tv), Zt = Z, p = p, m = m, n = n, ichols = ichols, 
                    nh = as.integer(nh), hchol = hchol, unidim = as.integer(unidim), 
                    info = as.integer(0), hobs = hobs, tol0 = object$tol0)
            if (out$info != 0) 
                stop("Error in diagonalization of H. Try option type=\"augment\".")
            
            H <- array(0, c(p, p, ((n - 1) * tv[2] + 1)))
            for (t in 1:((n - 1) * tv[2] + 1)) diag(H[, , t]) <- diag(out$ichols[,, out$hchol[t]])
            attry<-attributes(object$y)
            object$y <- t(out$yt)
            attributes(object$y)<-attry
            object$Z <- out$Z
            object$H <- H
            object$H_type <- "LDL decomposed"
        } else {
            object$H_type <- "Diagonal"
        }
    } else {
        T <- array(object$T, dim = c(m, m, (n - 1) * tv[3] + 1))
        R <- array(object$R, dim = c(m, r, (n - 1) * tv[4] + 1))
        Q <- array(object$Q, dim = c(r, r, (n - 1) * tv[5] + 1))
        H <- array(object$H, c(p, p, (n - 1) * tv[2] + 1))
        Z <- array(object$Z, dim = c(p, m, (n - 1) * tv[1] + 1))
        
        r2 <- r + p
        m2 <- m + p
        tv[5] <- max(tv[c(2, 5)])
        Qt2 <- array(0, c(r2, r2, 1 + (n - 1) * tv[5]))
        Qt2[1:r, 1:r, ] <- Q
        if (tv[2]) {
            Qt2[(r + 1):r2, (r + 1):r2, -n] <- H[, , -1]
        } else Qt2[(r + 1):r2, (r + 1):r2, ] <- H
        Zt2 <- array(0, c(p, m2, (n - 1) * tv[1] + 1))
        Zt2[1:p, 1:m, ] <- Z
        Zt2[1:p, (m + 1):m2, ] <- diag(p)
        Tt2 <- array(0, c(m2, m2, (n - 1) * tv[3] + 1))
        Tt2[1:m, 1:m, ] <- T
        Rt2 <- array(0, c(m2, r + p, (n - 1) * tv[4] + 1))
        Rt2[1:m, 1:r, ] <- R
        Rt2[(m + 1):m2, (r + 1):r2, ] <- diag(p)
        P12 <- P1inf2 <- matrix(0, m2, m2)
        P12[1:m, 1:m] <- object$P1
        P1inf2[1:m, 1:m] <- object$P1inf
        P12[(m + 1):m2, (m + 1):m2] <- H[, , 1]
        a12 <- matrix(0, m2, 1)
        a12[1:m, ] <- object$a1
        object$Z <- Zt2
        object$H <- array(0, c(p, p, 1))
        
        object$T <- Tt2
        object$R <- Rt2
        object$Q <- Qt2
        object$m <- m2
        object$k <- r2
        if(object$p==1){
            rownames(a12)<-c(rownames(object$a1),"eps")
        } else {
            rownames(a12)<-c(rownames(object$a1),paste0(rep("eps.",object$p),1:object$p))
        }
        object$a1 <- a12
        object$P1 <- P12
        object$P1inf <- P1inf2
        object$H_type <- "Augmented"
        
    }
    
    object
} 
