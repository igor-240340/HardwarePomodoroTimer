            .INCLUDE <tn13def.inc>

            .EQU HWTCNT_SEC = 1000                      ; Количество тиков аппаратного таймера, которое соответствует по длительности 1 секунде.
            
            ;.EQU TIM_MIN = 0                            ; Таймер на 00:10 минут.
            ;.EQU TIM_SEC = 10                           ;

            ;.EQU TIM_MIN = 0                            ; Таймер на 00:01 минут.
            ;.EQU TIM_SEC = 1                            ;

            .EQU TIM_MIN = 25                           ; Таймер на 25:00 минут.
            .EQU TIM_SEC = 0                            ;

            ;.EQU TIM_MIN = 1                            ; Таймер на минуту.
            ;.EQU TIM_SEC = 0                            ;
            
            ; Состояния таймера.
            .EQU TIMSTOP = 0                            ; Таймер остановлен/на паузе (счётчики хранят последние значения).
            .EQU TIMACTV = 1                            ; Таймер активен (счётчики обновляются).
            .EQU TIMEXPR = 2                            ; Таймер истёк (счётчики аппаратного таймера сброшены).
            .EQU TIMTOTL = 3                            ; Таймер на паузе, показываем суммарное время.
            .EQU TIMBLNK = 4                            ; Таймер мигает.

            .EQU VIBR_PIN = 4                           ; Номер пина, с которого будем дёргать вибру.

            .DEF HWTCNT_L = R0                          ; Накапливает количество тиков аппаратного таймера.
            .DEF HWTCNT_H = R1                          ;
            .DEF MINLEFT = R2                           ; Хранит количество оставшихся минут.
            .DEF SECLEFT = R3                           ; Хранит количество оставшихся секунд.
            .DEF TIMSTATE = R4                          ; Хранит состояние pomodoro-таймера (TIMSTOP, TIMACTV, TIMEXPR, TIMTOTL, TIMBLNK).
            
            .DEF TOTALMINL = R5                         ; Содержит суммарное время активности таймера с момента подачи питания.
            .DEF TOTALMINH = R6                         ;

            .DEF ARG1 = R24                             ; Для передачи аргументов перед RCALL.
            .DEF ARG2 = R25                             ; WARN: Не полагаться на то, что данные останутся неизменными после вызова.

            .CSEG
            .ORG 0x00

            ;
            ; Таблица векторов прерываний.
            RJMP RESET
            RJMP STARTBTN
            RJMP TOTALBTN
            RETI
            RETI
            RETI
            RJMP HWTIMTICK
            RETI
            RETI
            RETI

            ;
            ; Бэкапим временные регистры.
.MACRO PUSH_R16R17
            PUSH R16                                    ;
            PUSH R17                                    ;
.ENDM

            ;
            ; Восстанавливаем временные регистры.
.MACRO POP_R17R16
            POP R17                                     ;
            POP R16                                     ;
.ENDM

            ;
            ; Бэкапим регистры подпрограммы задержки в 100ms.
.MACRO PUSH_DELAY100MS
            PUSH R21                                    ;
            PUSH R22                                    ;
.ENDM

            ;
            ; Восстанавливаем регистры задержек.
.MACRO POP_DELAY100MS
            POP R22                                     ;
            POP R21                                     ;
.ENDM

            .INCLUDE "tm1637.asm"                     ; Подключаем здесь, чтобы модуль увидел макросы PUSH_R16R17/POP_R17R16.

            ;
            ; Нажата кнопка запуск/остановка таймера.
            ; После повторного нажатия, таймер продолжает тикать с того же самого места,
            ; т.е. не сбрасывается в ноль.
STARTBTN:   PUSH R16                                    ; Бэкапим общий регистр R16.
            IN R16, SREG                                ; Бэкапим SREG.
            PUSH R16                                    ;

            PUSH_DELAY100MS                             ; Бэкапим регистры, чтобы не сломать задержку в основном коде.
            RCALL DELAY100MS                            ; Ждём, пока пройдут все фронты от дребезка кнопки.
            POP_DELAY100MS                              ;

            LDI R16, (1 << INTF0)                       ; За время задержки могли прилететь фронты дребезга и установить флаг.
            OUT GIFR, R16                               ; Сбрасываем флаг.

            LDI R16, TIMBLNK                            ; Таймер истёк?
            EOR R16, TIMSTATE                           ;
            BREQ RESETTIM                               ; Да, активна индикация дисплеем, возвращаем таймер в начальное состояние.
                                                        ; Нет.
            LDI R16, TIMSTOP                            ; Таймер остановлен/на паузе?
            EOR R16, TIMSTATE                           ;
            BREQ RUNTIM                                 ; Да, запускаем.
            LDI R16, TIMSTOP                            ; Нет, таймер запущен.
            MOV TIMSTATE, R16                           ; Ставим на паузу аппаратный таймер.
            IN R16, TCCR0B                              ;
            ANDI R16, 0b11111000                        ; CS00 = CS01 = CS02 = 0.
            OUT TCCR0B, R16                             ;
            LDI R16, (1 << OCF0A) | (1 << TOV0)         ;
            OUT TIFR0, R16                              ;

            RJMP EXIT_ISR                               ;

RUNTIM:     LDI R16, TIMACTV                            ; Запускаем/возобновляем таймер.
            MOV TIMSTATE, R16                           ;
            LDI R16, (1 << CS01)                        ; Устанавливаем прескейлер в 8 (1.2MHz / 8).
            OUT TCCR0B, R16                             ; Это фактически запускает таймер.

            RJMP EXIT_ISR                               ;

RESETTIM:   LDI R16, TIMSTOP                            ; TIMSTATE = TIMSTOP.
            MOV TIMSTATE, R16                           ;
            RJMP EXIT_ISR                               ;

            ;
            ; Прерывание по аппаратному таймеру срабатывает каждые 0.001 сек (см. инициализацию таймера в RESET).
            ; Всего ожидаем HWTCNT_SEC прерываний, чтобы зафиксировать секунду.
HWTIMTICK:  PUSH R16                                    ; Бэкапим общий регистр.
            IN R16, SREG                                ; Бэкапим SREG.
            PUSH R16                                    ;
            LDI R16, 1                                  ; Двухбайтовый инкремент HWTCNT.
            ADD HWTCNT_L, R16                           ;
            CLR R16                                     ;
            ADC HWTCNT_H, R16                           ;

            LDI R16, LOW(HWTCNT_SEC)                    ; Младшие байты HWTCNT_SEC и HWTCNT совпали?
            EOR R16, HWTCNT_L                           ;
            BRNE EXIT_ISR                               ; Нет, продолжаем.
            LDI R16, HIGH(HWTCNT_SEC)                   ; Да, проверяем старшие.
            EOR R16, HWTCNT_H                           ; Старшие байты совпали?
            BRNE EXIT_ISR                               ; Нет, продолжаем.
                                                        ; Да, прошла секунда.
            ;
            ; Здесь реализован pomodoro-таймер.
            ; По прошествии TIM_MIN:TIM_SEC останавливаем и сбрасываем аппаратный таймер.
SEC_PASSED: CLR HWTCNT_L                                ; Сбрасываем счетчик аппаратного таймера.
            CLR HWTCNT_H                                ;

            OR SECLEFT, SECLEFT                         ; Количество оставшихся секунд равно нулю?
            BRNE DECSEC                                 ; Нет, можем безопасно уменьшить разряд секунд.
            DEC MINLEFT                                 ; Да, уменьшаем разряд минут.
            LDI R16, 59                                 ;
            MOV SECLEFT, R16                            ;
            
            RJMP EXIT_ISR                               ;

DECSEC:     DEC SECLEFT                                 ;
            MOV R16, MINLEFT                            ; Таймер истёк (MINLEFT == SECLEFT == 0)?
            OR R16, SECLEFT                             ;
            BREQ TIM_FIN                                ; Да, останавливаем.
            RJMP EXIT_ISR                               ; Нет, продолжаем.

TIM_FIN:    IN R16, TCCR0B                              ; Останавливаем и сбрасываем аппаратный таймер.
            ANDI R16, 0b11111000                        ; CS00 = CS01 = CS02 = 0.
            OUT TCCR0B, R16                             ;
            CLR R16                                     ; Сбрасываем аппаратный счётчик.
            OUT TCNT0, R16                              ;
            LDI R16, (1 << OCF0A) | (1 << TOV0)         ;
            OUT TIFR0, R16                              ;

            LDI R16, TIM_MIN                            ; Сбрасываем значение программного таймера.
            MOV MINLEFT, R16                            ;
            LDI R16, TIM_SEC                            ;
            MOV SECLEFT, R16                            ;

            LDI R16, TIMEXPR                            ; TIMSTATE = TIMEXPR.
            MOV TIMSTATE, R16                           ;
            
            LDI R16, 25                                 ; TOTALMIN += 25 минут.
            ADD TOTALMINL, R16                          ;
            CLR R16                                     ;
            ADC TOTALMINH, R16                          ;

            RJMP EXIT_ISR                               ;

            ;
            ; Нажата кнопка показа суммарного времени.
TOTALBTN:   PUSH R16                                    ; Бэкапим общий регистр.
            IN R16, SREG                                ; Бэкапим SREG.
            PUSH R16                                    ;

            PUSH_DELAY100MS                             ;
            RCALL DELAY100MS                            ;
            POP_DELAY100MS                              ;

            IN R16, PINB                                ; Кнопка нажата?
            SBRC R16, PB0                               ;
            RJMP TOTALBTN1                              ; Нет, оставляем таймер в состоянии паузы.
            LDI R16, TIMTOTL                            ; Да, ставим аппаратный таймер на паузу
            MOV TIMSTATE, R16                           ; и переходим в режим показа суммарного времени.
            IN R16, TCCR0B                              ;
            ANDI R16, 0b11111000                        ; CS00 = CS01 = CS02 = 0.
            OUT TCCR0B, R16                             ;
            LDI R16, (1 << OCF0A) | (1 << TOV0)         ; Очистка битов в TIFR0 работает установкой бита в 1.
            OUT TIFR0, R16                              ;
            RJMP EXIT_ISR                               ;

TOTALBTN1:  LDI R16, TIMSTOP                            ;
            MOV TIMSTATE, R16                           ;
            RJMP EXIT_ISR                               ;

            ;
            ; Сюда попадаем перед выходом из любого прерывания.
            ; Восстанавливает регистры перед выходом из прерывания.
EXIT_ISR:   POP R16                                     ; Восстанавливаем SREG.
            OUT SREG, R16                               ;
            POP R16                                     ; Восстанавливаем общий регистр R16.
            RETI                                        ;

            ;
            ; Reset.
RESET:      LDI YL, LOW(RAMEND)                         ; В ATtiny13 для адресации достаточно байта.
            OUT SPL, YL                                 ;

            ;
            ; Инициализируем аппаратный таймер.
            LDI R16, (1 << WGM01)                       ; Включаем CTC mode.
            OUT TCCR0A, R16                             ;
            LDI R16, 149                                ; Прерывание по таймеру - каждые 150 тиков (0.001 секунды с учётом прескейлера).
            OUT OCR0A, R16                              ; Почему 149, а не 150?
            LDI R16, (1 << OCIE0A)                      ; Потому что после первого тика внутренний счетчик будет равен нулю.
            OUT TIMSK0, R16                             ;

            CLR HWTCNT_L                                ; Сбрасываем счётчик тиков аппаратного таймера.
            CLR HWTCNT_H                                ;

            CBI DDRB, DDB1                              ; Настраиваем кнопку запуска/остановки таймера.
            SBI PORTB, PB1                              ;

            CBI DDRB, DDB0                              ; Настраиваем кнопку показа суммарного времени.
            SBI PORTB, PB0                              ;

            LDI R16, (1 << ISC01 | 1 << ISC00)          ; Разрешаем прерывание по INT0
            OUT MCUCR, R16                              ; по фронту (при отпускании кнопки запуска/остановки таймера).
            LDI R16, (1 << INT0 | 1 << PCIE)            ; Также разрешаем прерывание по изменению на пине PB0.
            OUT GIMSK, R16                              ;
            SBI PCMSK, PCINT0                           ;

            ;
            ; Инициализируем pomodoro-таймер.
            LDI R16, TIM_MIN                            ;
            MOV MINLEFT, R16                            ;
            CLR SECLEFT                                 ;
            LDI R16, TIM_SEC                            ;
            MOV SECLEFT, R16                            ;
            CLR TIMSTATE                                ; TIMSTATE = TIMSTOP.

            CLR TOTALMINL                               ; TOTALMIN = 0.
            CLR TOTALMINH                               ;

            ;
            ; Настройки для вибры.
            SBI DDRB, VIBR_PIN                          ;
            CBI PORTB, VIBR_PIN                         ;

            ;
            ; Инициализируем дисплей.
            RCALL INIT_DISP                             ;

            SEI                                         ;

            ;
            ; Main.
MAIN:       RCALL LIGHTALL                              ; Тестовая индикация: вибрируем и мигаем всеми сегментами.
            SBI PORTB, VIBR_PIN                         ;
            RCALL DELAY200MS                            ;
            RCALL CLEARDISP                             ;
            CBI PORTB, VIBR_PIN                         ;
            RCALL DELAY100MS                            ;
            
CHECKTIM:   LDI R16, TIMEXPR                            ; Таймер истёк?
            EOR R16, TIMSTATE                           ;
            BREQ BLINKVIB                               ; Да, мигаем с вибрирацией один раз.

            LDI R16, TIMBLNK                            ; Вибрация во время индикации отработала?
            EOR R16, TIMSTATE                           ;
            BREQ BLINK                                  ; Да, далее просто мигаем.

            LDI R16, TIMTOTL                            ; Нет.
            EOR R16, TIMSTATE                           ; Нажата кнопка показа суммарного времени?
            BREQ SHOWTOTAL                              ; Да, показываем суммарное время.

            RJMP SHOWTIM                                ; Нет, таймер активен либо на паузе, выводим оставшееся время.

BLINKVIB:   LDI R16, TIMBLNK                            ; TIMEXPR -> TIMBLNK.
            MOV TIMSTATE, R16                           ;
            SBI PORTB, VIBR_PIN                         ; Вибрация.
BLINK:      RCALL LIGHTALL                              ; Индикация.
            RCALL DELAY200MS                            ;
            RCALL CLEARDISP                             ;
            CBI PORTB, VIBR_PIN                         ;
            RCALL DELAY200MS                            ;
            RJMP CHECKTIM                               ;

            ;
            ; Показывает суммарное время активности таймера в часах и минутах.
            ; NOTE: Максимальное значение ограничиваем 15 часами, т.е. 900 минутами.
SHOWTOTAL:  MOV ARG1, TOTALMINL                         ;
            MOV ARG2, TOTALMINH                         ;
            RCALL DIV60                                 ; ARG1 - количество часов. ARG2 - количество минут.
            MOV R20, ARG2                               ; Бэкапим минуты.
            RCALL DIV10                                 ; ARG1 - числовое значение старшего разряда часов. ARG2 - числовое значение младшего разряда часов.
            RCALL MAPTOCODE                             ; ARG1 - код старшего разряда часов.
            PUSH ARG1                                   ;
            MOV ARG1, ARG2                              ; Получаем код младшего разряда часов.
            RCALL MAPTOCODE                             ;
            LDI R16, COLON                              ; Младший разряд часов будет выведен на индикаторе с двоеточием.
            OR ARG1, R16                                ; Добавляем код двоеточия.
            PUSH ARG1                                   ;
            MOV ARG1, R20                               ; Восстанавливаем минуты.
            RCALL DIV10                                 ; ARG1 - числовое значение старшего разряда минут. ARG2 - числовое значение младшего разряда минут.
            RCALL MAPTOCODE                             ; Получаем код старшего разряда минут.
            PUSH ARG1                                   ;
            MOV ARG1, ARG2                              ; Получаем код младшего разряда минут.
            RCALL MAPTOCODE                             ;

            LDI ARG2, 3                                 ; Выводим младший разряд минут.
            RCALL SHOW_DIGIT                            ; ARG1 - уже сожержит код младшего разряда минут.

            POP ARG1                                    ; Код старшего разряда минут.
            LDI ARG2, 2                                 ; Выводим старший разряд минут.
            RCALL SHOW_DIGIT                            ;

            POP ARG1                                    ; Код младшего разряда часов.
            LDI ARG2, 1                                 ; Выводим младший разряд часов.
            RCALL SHOW_DIGIT                            ;

            POP ARG1                                    ; Код старшего разряда часов.
            LDI ARG2, 0                                 ; Выводим старший разряд часов.
            RCALL SHOW_DIGIT                            ;

            RJMP CHECKTIM                               ;

SHOWTIM:    MOV ARG1, MINLEFT                           ; ARG1 = MINLEFT / 10 (числовое значение cтаршего разряда минут).
            RCALL DIV10                                 ; ARG2 = MINLEFT % 10 (числовое значение младшего разряда минут).
            RCALL MAPTOCODE                             ; Мапим числовое значение старшего разряда минут в код индикатора.
            PUSH ARG1                                   ; Бэкапим код старшего разряда минут.
            MOV ARG1, ARG2                              ; Мапим числовое значение младшего разряда минут в код индикатора.
            RCALL MAPTOCODE                             ;
            LDI R16, COLON                              ; Младший разряд минут будет выведен на индикаторе с двоеточием.
            OR ARG1, R16                                ; Добавляем код двоеточия.
            PUSH ARG1                                   ; Бэкапим код младшего разряда минут.

            MOV ARG1, SECLEFT                           ; ARG1 = SECLEFT / 10 (старший разряд секунд).
            RCALL DIV10                                 ; ARG2 = SECLEFT % 10 (младший разряд секунд).
            RCALL MAPTOCODE                             ; Мапим числовое значение старшего разряда секунд в код индикатора.
            PUSH ARG1                                   ; Бэкапим код старшего разряда секунд.
            MOV ARG1, ARG2                              ; Мапим числовое значение младшего разряда секунд в код индикатора.
            RCALL MAPTOCODE                             ; ARG1 - код младшего разряда секунд.

            LDI ARG2, 3                                 ; Выводим младший разряд секунд.
            RCALL SHOW_DIGIT                            ; ARG1 - уже сожержит код младшего разряда секунд.

            POP ARG1                                    ; Восстанавливаем старший разряд секунд.
            LDI ARG2, 2                                 ; Выводим старший разряд секунд.
            RCALL SHOW_DIGIT                            ;

            POP ARG1                                    ; Восстанавливаем младший разряд минут.
            LDI ARG2, 1                                 ; Выводим младший разряд минут.
            RCALL SHOW_DIGIT                            ;

            POP ARG1                                    ; Восстанавливаем старший разряд минут.
            LDI ARG2, 0                                 ; Выводим старший разряд минут.
            RCALL SHOW_DIGIT                            ;

            RJMP CHECKTIM                               ;

END:        RJMP END                                    ;

            ;
            ; Для чисел от 0 до 9 возвращает код цифры TM1637.
            ;
            ; Вход:
            ; - ARG1: Число от 0 до 9.
            ;
            ; Выход:
            ; - ARG1: Код цифры.
MAPTOCODE:  LDI ZH, HIGH(DIGITS << 1)                   ; ARG1 = DIGITS[ARG1].
            LDI ZL, LOW(DIGITS << 1)                    ;
            ADD ZL, ARG1                                ;
            CLR R16                                     ;
            ADC ZH, R16                                 ;
            LPM ARG1, Z                                 ;
            RET

            ;
            ; Целочисленное деление на 10 (схема с неподжвижным делимым, с восстановлением остатка).
            ;
            ; NOTE: Это ad hoc деление для значения оставшихся минут/секунд.
            ; Поскольку наш таймер не превышает 25 минут, то значение передаваемого делимого никогда не превысит 59 (по значению секунд).
            ; При этом, поскольку делитель B всегда равен 10, то значение неполного частного никогда не превысит 5 (0b00000101).
            ; Поэтому мы начинаем вычисление двоичных разрядов неполного частного сразу с третьего (индекс 2).
            ; Пример: передали 59 секунд, после деления: Q = 5, R = 9.
            ;
            ; Вход:
            ; - ARG1: Делимое A - число оставшихся минут или секунд (всегда <= 59).
            ;
            ; Выход:
            ; - ARG1: Неполное частное Q (числовое значение разряда десятков).
            ; - ARG2: Остаток R (числовое значение разряда единиц).
DIV10:      MOV R16, ARG1                               ; R = A.
            CLR R18                                     ; Q = 0.
            LDI R19, 3                                  ; Количество оставшихся к вычислению разрядов частного Q.
            LDI R17, 40                                 ; B = B * 4 = B * 2^(R19 - 1) = B * 0b00000100 = B << 2 = 0b00101000.

DIV10_1:    PUSH R16                                    ; Бэкапим актуальное значение делимого/остатка.
            SUB R16, R17                                ; R - B > 0?
            BRPL SETQ1                                  ; Да, устанавливаем разряд частного Q[R19 - 1] в 1.
            CLC                                         ; Нет, устанавливаем разряд частного в 0.
            ROL R18                                     ; Q[R19 - 1] = 0.
            POP R16                                     ; Восстанавливаем последний положительный остаток R.
            RJMP DIV10_2                                ;
SETQ1:      SEC                                         ; Q[R19 - 1] = 1.
            ROL R18                                     ;
            POP ARG1                                    ; В стеке хранится старое значение R - выбрасываем его.
DIV10_2:    DEC R19                                     ; Вычислили все разряды частного?
            BREQ DIV10FIN                               ; Да, возвращаем значения Q и R.
            ROR R17                                     ; Нет, продолжаем. B = B / 2 = B * 2^(R19 - 1).
            RJMP DIV10_1                                ;
      
DIV10FIN:   MOV ARG1, R18                               ; ARG1 = Q.
            MOV ARG2, R16                               ; ARG2 = R.
            RET

            ;
            ; Целочисленное деление на 60 (схема с неподжвижным делимым, с восстановлением остатка).
            ;
            ; NOTE: Это ad hoc деление для перевода суммарного времени активности таймера в минутах в часы и минуты.
            ; Поскольку мы ограничиваем суммарное время активности таймера 15 часами, то значение передаваемого делимого
            ; никогда не превысит 15 * 60 = 900 минут.
            ; При этом, поскольку делитель B всегда равен 60, то значение неполного частного никогда не превысит 15 (0b00001111).
            ; Поэтому мы начинаем вычисление двоичных разрядов неполного частного сразу с четвертого (индекс 3).
            ; Пример: передали 75 минут (три раза по 25 минут), после деления: Q = 1 час, R = 15 минут.
            ;
            ; Вход:
            ; - ARG1: Младший байт делимого A - суммарное количество минут активности таймера (всегда <= 15 * 60 = 900).
            ; - ARG2: Старший байт делимого A.
            ;
            ; Выход:
            ; - ARG1: Неполное частное Q (количество часов).
            ; - ARG2: Остаток R (количество минут).
DIV60:      MOV R16, ARG1                               ; R = A.
            MOV R17, ARG2                               ;
            CLR ARG1                                    ; Q = 0.
            
            LDI R20, 4                                  ; Количество вычисляемых разрядов частного.
            MOV ARG2, R20                               ;

            LDI R18, LOW(480)                           ; Инициализируем частичное произведение B = B * 2^(ARG2 - 1),
            LDI R19, HIGH(480)                          ; где 2^(ARG2 - 1) - это вес текущего вычисляемого разряда частного Q[ARG2 - 1].
            
CONTDIV60:  PUSH R18                                    ; Бэкапим последнее положительное значение частичного произведения B.
            PUSH R19                                    ;
            
            COM R18                                     ; Вычисляем доп. код частичного произведения B.
            COM R19                                     ;
            LDI R20, 1                                  ;
            ADD R18, R20                                ;
            CLR R20                                     ;
            ADC R19, R20                                ;

            PUSH R16                                    ; Бэкапим последний неотрицательный остаток R.
            PUSH R17                                    ;

            ADD R16, R18                                ; Вычитаем частичное произведение B из делимого/остатка.
            ADC R17, R19                                ; R = R - (B * 2^(ARG2 - 1)) < 0?
            BRMI DIV60_2                                ; Да, устанавливаем текущий разряд частного в ноль и восстанавливаем остаток.
            SEC                                         ; Нет, устанавливаем разряд частного в единицу
            ROL ARG1                                    ; и выбрасываем последний положительный остаток из стека.
            POP R20                                     ;
            POP R20                                     ;
            RJMP DIV60_3                                ;

DIV60_2:    CLC                                         ;
            ROL ARG1                                    ;
            POP R17                                     ; Восстанавливаем последний положительный остаток.
            POP R16                                     ;

DIV60_3:    POP R19                                     ; Восстанавливаем положительное значение частичного произведения B.
            POP R18                                     ;

            DEC ARG2                                    ; Вычислили все разряды частного?
            BREQ DIV60FIN                               ; Да, возвращаем часы и минуты в ARG1 и ARG2 соответственно.
            CLC                                         ; Нет, переходим к следующему разряду частного.
            ROR R19                                     ; B = B * 2^(ARG2 - 1).
            ROR R18                                     ;
            RJMP CONTDIV60                              ;

DIV60FIN:   MOV ARG2, R16                               ; ARG1 уже содержит Q. А остаток R всегда меньше 60, поэтому берем только младший байт.
            RET

            ;
            ; Задержка в 200ms.
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY200MS: LDI R21, 2
            LDI R22, 56
            LDI R23, 171
DELAY200MS1:DEC R23
            BRNE DELAY200MS1
            DEC R22
            BRNE DELAY200MS1
            DEC R21
            BRNE DELAY200MS1
            RJMP PC+1
            RET

            ;
            ; Задержка в 100ms.
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
;DELAY200MS: LDI R21, 156
;            LDI R22, 213
;DELAY200MS1:DEC R22
;            BRNE DELAY200MS1
;            DEC R21
;            BRNE DELAY200MS1
;            NOP
;            RET

            ;
            ; Задержка в 500ms.
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
;DELAY200MS: LDI R21, 4
;            LDI R22, 12
;            LDI R23, 50
;DELAY200MS1:DEC R23
;            BRNE DELAY200MS1
;            DEC R22
;            BRNE DELAY200MS1
;            DEC R21
;            BRNE DELAY200MS1
;            NOP
;            RET

            ;
            ; Задержка в 100ms.
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY100MS: LDI R21, 156
            LDI R22, 213
DLAY100MS1: DEC R22
            BRNE DLAY100MS1
            DEC R21
            BRNE DLAY100MS1
            NOP
            RET

            ;
            ; Коды цифр для TM1637 от 0 до 9.
DIGITS:     .DB 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

            ;
            ; Таблица занятых/свободных регистров.
; [X] R0
; [X] R1
; [X] R2
; [X] R3
; [X] R4
; [X] R5 - Младший байт суммарного времени активности таймера с момента подачи питания.
; [X] R6 - Старший байт суммарного времени активности таймера с момента подачи питания.
; [-] R7
; ...
; [-] R15
; ==================================
; [X] R16 - Временные данные.
; [X] R17 - Временные данные.
; [X] R18 - Временные данные.
; [X] R19 - Временные данные.
; [X] R20 - Временные данные.
; [X] R21 - Под задержки.
; [X] R22 - Под задержки.
; [X] R23 - Под задержки.
; [X] R24 - Для передачи аргументов.
; [X] R25 - Для передачи аргументов.
; [-] X R26:R27
; [-] Y R28:R29
; [-] Z R30:R31