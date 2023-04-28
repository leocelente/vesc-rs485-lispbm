(uart-start 115200)

(define uart-buf (array-create 100))

(gpio-configure 'pin-rs485de 'pin-mode-out)
(gpio-configure 'pin-rs485re 'pin-mode-out)
(gpio-write 'pin-rs485de 0) 
(gpio-write 'pin-rs485re 0)
    
;; General missing comparison functions
(defun min (x y) (if (< x y) x y ))
(defun max (x y) (if (> x y) x y ))

(define default-alpha 100) ; TODO: add default alpha interface
;; RPM <-> rad/s conversion
(defun to-omega (rpm) (* 0.10472 rpm))
(defun to-rpm (omega) (* 9.5492 omega))
;; Smallest timestep 
(define dt 0.005)
;; Microsecond delay between steps
(define delay (to-i (* dt 1000000)))

;; UART Byte time
(define uart-byte-time (/ (* (+ 1 8 1) 1000000) 115200))

;; Transmits via RS485 UART with Hardware Control Flow (~RE/DE)
;; https://electronics.stackexchange.com/questions/153500/correctly-using-re-and-de-with-rs485
(defun rs485-write (buffer) 
    (progn 
        (gpio-write 'pin-rs485re 1) ; we are not receveing (~Recv Enable HIGH)
        (gpio-write 'pin-rs485de 1) ; we are transmitting (Driver Enable HIGH)
        (uart-write buffer)

        (yield (* uart-byte-time (- (buflen buffer) 1))) 
        ;; The delay is recommended in case the UART shift register is not done, 
        ;;  even if the UART buffer is clear. As the latter is a commonly used
        ;;  to define the end of transmision.
        ;;  https://barrgroup.com/embedded-systems/how-to/rs-485-transmit-enable-signal
        ;; And in the case o ChibiOS/RT there is common practice to wait for 
        ;;  RTOS queues to clear that may add further delay
        ;; ~85us is the expected time to transmit a byte (1+8+1) / 115200
        
        (gpio-write 'pin-rs485de 0) ; we are not transmitting (Driver Enable LOW)
        (gpio-write 'pin-rs485re 0) ; we are receveing (~Recv Enable LOW)
    )
)

(defun update-rpm (i steps increment) 
    (cond ( (< i steps)
            (progn 
                (set-rpm (+ (get-rpm) increment)) 
                (yield delay)
                (update-rpm (+ i 1) steps increment)
            )
        )
    )
)

(defun set-omega (omega alpha)
    (let (  (current-omega (to-omega (get-rpm)))
            (delta-omega (- omega current-omega))
            (delta-t (abs (/ delta-omega alpha)))
            (n-steps (/ delta-t dt))
            (d-omega (/ delta-omega n-steps))
            (i-steps (to-i n-steps))
         )
        (progn 
            (rs485-write (str-from-n (* i-steps dt) (str-merge rs485-id  " %2.3f\n")))  
            (update-rpm 0 i-steps (to-rpm d-omega))
            (set-rpm (to-rpm omega)); correct quantization errors
        )
    )
)

(defun update-duty-cycle (i steps increment) 
    (cond ( (< i steps)
            (progn 
                (set-duty (+ (get-duty) increment))
                (yield delay)
                (update-duty-cycle (+ i 1) steps increment)
            )
        )
    )
)


;; Sets duty cyle gradually to <setpoint> in % at rate <alpha> in %/s 
;; (cmd-duty <setpoint> <alpha>)
(defun cmd-duty (args) 
   (let (
        (setpoint (str-to-f (first args)))
        (alpha (str-to-f (first (rest args))))
        (alpha 0.3)
        (current-dc (get-duty))
        (delta-dc (- setpoint current-dc))
        (delta-t (abs (/ delta-dc alpha)))
        (n-steps (/ delta-t dt))
        (d-dc (/ delta-dc n-steps))
        (i-steps (to-i n-steps))
    ) 
    (progn
        (print args setpoint alpha)
        (rs485-write (str-from-n (* i-steps dt) (str-merge rs485-id  " %2.3f\n")))  
        (update-duty-cycle 0 i-steps d-dc)
        (set-duty setpoint)
    )
   )
)

;; Conevience function set rotational speed using RPM
(defun my-set-rpm (rpm alpha) (set-omega (to-omega rpm) alpha))

;; Sets speed gradually to <omega> in rad/s at angular acceleration <alpha> in rad/s2 
;; (cmd-speed <omega> <alpha>)
(defun cmd-speed (args) 
    (progn 
        (set-omega (first args) (first (rest args)))
        (rs485-write (str-from-n (first args) (str-merge rs485-id  " %2.3f\n")))
))

;; Sets speed gradually to <rpm> in RPM at angular acceleration <alpha> in rad/s2 
;; (cmd-rpm <rpm> <alpha>)
(defun cmd-rpm (args) 
    (progn 
        (my-set-rpm (first args) (first (rest args)))
        (rs485-write (str-from-n (first args) (str-merge rs485-id  " %2.3f\n")))
))

;; Returns current encoder position in degrees
;; (cmd-encoder )
(defun cmd-encoder (args) 
    (progn 
        (rs485-write (str-from-n (get-encoder) (str-merge rs485-id  " %2.3f\n")))
))

(defun cmd-reset-encoder (args) 
    (progn
        (set-encoder 0)
        (rs485-write (str-from-n (get-encoder) (str-merge rs485-id  " %2.3f\n")))
    )
)

(defun cmd-temp-motor (args)
    (rs485-write (str-from-n (get-temp-mot) (str-merge rs485-id  " %2.3f\n")))
)

(defun cmd-temp-mosfet (args)
    (rs485-write (str-from-n (get-temp-fet) (str-merge rs485-id  " %2.3f\n")))
)

(defun cmd-temp (args)
    (progn 
        (rs485-write (str-merge (str-from-n (get-temp-mot) "0 %2.3f") "," (str-from-n (get-temp-fet) " %2.3f\n") ))
    )
)

(define rs485-id "0")

(defun process (buffer) 
    (progn (print "buffer in process:" buffer)
        (let (  (tokens (str-split buffer " ")) )
        (progn (print "tokens:" tokens)
        (if (> (length tokens) 1) 
            (let (
                    (id  (first tokens))
                    (cmd  (first (rest tokens)))
                    (args (rest (rest tokens)))
                  )
                    (progn (print tokens id cmd args)
                            (if (= 0 (str-cmp id rs485-id))
                                (cond
                                    ((= 0 (str-cmp cmd "speed")) (cmd-speed args))
                                    ((= 0 (str-cmp cmd "rpm")) (cmd-rpm args))
                                    ((= 0 (str-cmp cmd "duty")) (cmd-duty args))
                                    ((= 0 (str-cmp cmd "d")) (cmd-duty args))
                                    ((= 0 (str-cmp cmd "encoder")) (cmd-encoder args))
                                    ((= 0 (str-cmp cmd "e")) (cmd-encoder args))
                                    ((= 0 (str-cmp cmd "reset_encoder")) (cmd-reset-encoder args))
                                    ((= 0 (str-cmp cmd "r")) (cmd-reset-encoder args))
                                    ((= 0 (str-cmp cmd "temp_motor")) (cmd-temp-motor args))
                                    ((= 0 (str-cmp cmd "temp_mosfet")) (cmd-temp-mosfet args))
                                    ((= 0 (str-cmp cmd "temp")) (cmd-temp args))
                                    ((= 0 (str-cmp cmd "t")) (cmd-temp args))
                                    (t (rs485-write "CMD_NOT_FOUND\n"))
                                )        
                                (progn (print "not to me") )
                            )
                        )
                    )
                    (progn (print "not command") )
                )    
            )
        )
    )
)

(defun commands-handler () 
    (loopwhile t
        (progn
            (uart-read-until uart-buf 100 0 10) ; 10 is the \n
            (print "buffer pre-clr" uart-buf)
;            (bufclear uart-buf 0 (- (str-len uart-buf) 1) ) ; remove newline
            (print "buffer to process" uart-buf)
            (process uart-buf)
        )
    )
)

;; Procedure that monitors `command-handler` thread, in case o failure it restarts.
(defun run () 
    (progn 
        (spawn-trap 512 commands-handler )
        (recv  ((exit-error (? tid) (? e)) 
            (progn 
                (print "Thread failed.... Restarting" e)
                (run) ; is this going to (eventually) eat memory?
            ))
            ((exit-ok    (? tid) (? v)) (print "Commands Thread exited"))
        )            
    )
)

(yield 10000) ; wait 10ms
(set-duty 0)
(run)
