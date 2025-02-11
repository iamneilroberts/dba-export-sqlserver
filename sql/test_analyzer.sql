-- Previous content remains the same until the transaction scoring section
    TransactionScore = (
        CASE
            -- Name-based scoring (40%)
            WHEN TableName LIKE '%Tran[_]%' OR TableName LIKE '%Trans[_]%' THEN 0.40
            WHEN TableName LIKE '%Visit%' OR TableName LIKE '%Encounter%' THEN 0.40
            WHEN TableName LIKE '%Claim%' OR TableName LIKE '%Activity%' THEN 0.40
            WHEN TableName LIKE '%Event%' OR TableName LIKE '%Entry%' THEN 0.40
            WHEN TableName LIKE '%Record%' OR TableName LIKE '%Order%' THEN 0.40
            -- Healthcare specific patterns (40%)
            WHEN TableName LIKE '%Registration%' THEN 0.40
            WHEN TableName LIKE '%Admission%' THEN 0.40
            WHEN TableName LIKE '%Patient%' THEN 0.40
            WHEN TableName LIKE '%Appointment%' THEN 0.40
            WHEN TableName LIKE '%Schedule%' THEN 0.40
            -- Supporting patterns (25%)
            WHEN TableName LIKE '%Log%' OR TableName LIKE '%History%' THEN 0.25
            WHEN TableName LIKE '%Audit%' OR TableName LIKE '%Journal%' THEN 0.25
            ELSE 0.0
        END +
        -- Volume-based scoring (30%)
        CASE
            WHEN TotalRows >= 50000 THEN 0.30
            WHEN TotalRows >= 10000 THEN 0.25
            WHEN TotalRows >= 5000 THEN 0.20
            WHEN TotalRows >= 1000 THEN 0.15
            ELSE 0.10
        END +
        -- Date column scoring (30%)
        CASE
            WHEN DateColumns IS NOT NULL THEN 0.30
            ELSE 0.0
        END
    ),