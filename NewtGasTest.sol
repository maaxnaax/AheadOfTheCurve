// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;


contract NewtGasTest {
    using SlightlySafeMath for *;

    // Constant values used in ramping A calculations
    uint256 private constant A_PRECISION = 100;
    uint256 private constant MAX_LOOP_LIMIT = 300;
    uint16 private numTokens;
    uint16 private testIterations;
    uint16 private numIterations;

    struct Inputs {
        uint256[] xp;
        uint256 d;
    }

    Inputs[] allInputs;

    constructor() {
        numTokens = 3;
        testIterations = 40;
        numIterations = 255;

        fillAllInputs();
    }

    function generateRandomInput() internal view returns (uint256[] memory, uint256) {
        uint256[] memory xp = new uint256[](numTokens);
        uint256 totalValue = 10**18; // Total value of the pool, adjust as needed
        
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenValue = getRandomTokenValue(totalValue);
            xp[i] = tokenValue;
            totalValue = totalValue.sub(tokenValue);
        }
        uint256 d = getRandomD(totalValue);
        
        return (xp, d);
    }
    
    function getRandomTokenValue(uint256 maxValue) internal view returns (uint256) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (maxValue.add(1));
        return randomValue;
    }
    
    function getRandomD(uint256 maxValue) internal view returns (uint256) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (maxValue.add(1));
        return randomValue;
    }

    function fillAllInputs() internal {
        for (uint256 i = 0; i < testIterations; i++) {
            (uint256[] memory xp, uint256 d) = generateRandomInput();
            Inputs memory inputs = Inputs(xp, d);
            allInputs.push(inputs);
        }
    }

    
    // ---------------- Binary Search ----------------

    function getYDBinarySearch(
        uint256 a,
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d
    ) internal view  returns (uint256) {
        // uint256 numTokens = xp.length;
        require(tokenIndex < numTokens, "Token not found");

        uint256 c = d;
        uint256 s;
        uint256 nA = a.mul(numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                s = s.add(xp[i]);
                c = c.mul(d).div(xp[i].mul(numTokens));
            }
        }
        c = c.mul(d).mul(A_PRECISION).div(nA.mul(numTokens));

        uint256 b = s.add(d.mul(A_PRECISION).div(nA));
        uint256 low = 0;
        uint256 high = d;
        uint256 y;
        while (high.sub(low) > 1) {
            y = low.add(high).div(2);
            // if (calculateEquation(a, xp, d, c, b, y) > 0) {
            if (calculateEquation(d, c, b, y) > 0) {
                high = y;
            } else {
                low = y;
            }
        }
        return low;
    }     

    function calculateEquation(
        uint256 d,
        uint256 c,
        uint256 b,
        uint256 y
    ) internal pure returns (int256) {
        int256 result = int256(y * y + c) / int256(2 * y + b - d);
        return result;
    }

    // ---------------- Newtons Method ------------------

    function getYDNewtonsMethod(
        uint256 a,
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d
    ) internal view returns (uint256) {
        require(tokenIndex < numTokens, "Token not found");

        uint256 c = d;
        uint256 s;
        uint256 nA = a.mul(numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                s = s.add(xp[i]);
                c = c.mul(d).div(xp[i].mul(numTokens));
                // If we were to protect the division loss we would have to keep the denominator separate
                // and divide at the end. However this leads to overflow with large numTokens or/and D.
                // c = c * D * D * D * ... overflow!
            }
        }
        c = c.mul(d).mul(A_PRECISION).div(nA.mul(numTokens));

        uint256 b = s.add(d.mul(A_PRECISION).div(nA));
        uint256 yPrev;
        uint256 y = d;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = y.mul(y).add(c).div(y.mul(2).add(b).sub(d));
            if (y.within1(yPrev)) {
                return y;
            }
        }
        revert("Approximation did not converge");
    }  



    // ------------------ QNM --------------------

    function getYDQuasiNewtonsMethod(
        uint256 a,
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d
    ) internal pure returns (uint256) {
        require(tokenIndex < xp.length, "Token not found");

        uint256 c = d;
        uint256 denominator = 0;

        for (uint256 i = 0; i < xp.length; i++) {
            if (i != tokenIndex) {
                denominator += xp[i] * xp.length;
                c = c * d / (xp[i] * xp.length);
            }
        }

        c = c * d * A_PRECISION / denominator;

        uint256 s;
        uint256 nA = a * xp.length;

        for (uint256 i = 0; i < xp.length; i++) {
            s += xp[i];
        }

        uint256 b = s + d * A_PRECISION / nA;

        uint256 yPrev;
        uint256 y = d;

        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - d);

            // if (within1(y, yPrev)) {
            if (y.within1(yPrev)) {
                return y;
            }
        }

        revert("Approximation did not converge");
    }


    // -------------- Secant -----------------

    function getYDSecantMethod(
        uint256 a,
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d
    ) internal view returns (uint256) {
        require(tokenIndex < numTokens, "Token not found");

        uint256 c = d;
        uint256 s;
        uint256 nA = a.mul(numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                s = s.add(xp[i]);
                c = c.mul(d).div(xp[i].mul(numTokens));
            }
        }
        c = c.mul(d).mul(A_PRECISION).div(nA.mul(numTokens));

        uint256 b = s.add(d.mul(A_PRECISION).div(nA));
        uint256 yPrev;
        uint256 y = d;
        uint256 yPrevPrev;

        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrevPrev = yPrev;
            yPrev = y;
            y = calculateEquationSec(d, c, b, y);

            // Check if the difference between current and previous y values is within the tolerance
            if (y.sub(yPrev).within1(yPrevPrev.sub(yPrev))) {
                return y;
            }
        }

        revert("Approximation did not converge");
    }

    function calculateEquationSec(
        uint256 d,
        uint256 c,
        uint256 b,
        uint256 y
    ) internal pure returns (uint256) {
        uint256 numerator = y.mul(y).add(c);
        uint256 denominator = y.mul(2).add(b).sub(d);
        return numerator.div(denominator);
    }


    // ------------------- Broydens Method -----------------
    struct BroydenState {
        uint256[] jacInv;
        uint256[] jac;
        uint256 yPrev;
        uint256 y;
    }

    function getYDBroydenMethod(
        uint256 a,
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d
    ) internal view returns (uint256) {
        require(tokenIndex < numTokens, "Token not found");

        uint256 c = d;
        uint256 s;
        uint256 nA = a.mul(numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                s = s.add(xp[i]);
                c = c.mul(d).div(xp[i].mul(numTokens));
            }
        }
        c = c.mul(d).mul(A_PRECISION).div(nA.mul(numTokens));

        // uint256 b = s.add(d.mul(A_PRECISION).div(nA));
        BroydenState memory state;
        state.yPrev = d;
        state.y = d;
        state.jacInv = initializeInverseJacobian(tokenIndex, d);

        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            state.yPrev = state.y;
            state.jac = calculateJacobian(tokenIndex, xp, d, state.y);
            uint256 deltaY = state.y.sub(state.yPrev);
            uint256[] memory update = calculateBroydenUpdate(state.jac, state.jacInv, deltaY);
            updateSolutionEstimate(state, update, tokenIndex);

            if (state.y.within1(state.yPrev)) {
                return state.y;
            }
        }
        revert("Approximation did not converge");
    }

    function initializeInverseJacobian(uint256 tokenIndex, uint256 d)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory jacInv = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            jacInv[i] = (i == tokenIndex) ? d : 0;
        }
        return jacInv;
    }

    function calculateJacobian(
        uint256 tokenIndex,
        uint256[] memory xp,
        uint256 d,
        uint256 y
    ) internal view returns (uint256[] memory) {
        uint256[] memory jac = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                jac[i] = d.mul(d).div(xp[i].mul(numTokens)).mul(2).add(y.mul(2));
            } else {
                jac[i] = d.mul(d).div(xp[i].mul(numTokens)).mul(2).add(y.mul(3));
            }
        }
        return jac;
    }

    function calculateBroydenUpdate(
        uint256[] memory jac,
        uint256[] memory jacInv,
        uint256 deltaY
    ) internal view returns (uint256[] memory) {
        uint256[] memory update = new uint256[](numTokens);
        uint256 denominator = 0;

        for (uint256 i = 0; i < numTokens; i++) {
            update[i] = jacInv[i].mul(deltaY);
            denominator = denominator.add(jacInv[i].mul(jac[i]));
        }

        require(denominator != 0, "Denominator is zero");

        for (uint256 i = 0; i < numTokens; i++) {
            update[i] = update[i].div(denominator);
        }

        return update;
    }

    function updateSolutionEstimate(
        BroydenState memory state,
        uint256[] memory update,
        uint256 tokenIndex
    ) internal view {
        for (uint256 i = 0; i < numTokens; i++) {
            if (i != tokenIndex) {
                state.jacInv[i] = state.jacInv[i].sub(state.jacInv[tokenIndex].mul(update[i]));
            }
        }
        state.jacInv[tokenIndex] = state.jacInv[tokenIndex].add(update[tokenIndex]);
        state.y = state.y.mul(state.y).add(update[tokenIndex]).div(state.y.mul(2).sub(state.yPrev));
    }



    // -------------------------- TESTS -----------------------------
    // -------------------------- TESTS -----------------------------





    function gasTestBS() external view {
        for (uint16 i = 0; i < testIterations; i++) {

            uint256[] memory xp = allInputs[i].xp;
            uint256 tokenIndex = i % 3;
            uint256 d = allInputs[i].d;
            getYDBinarySearch(100, tokenIndex, xp, d);
        }
    }

    function gasTestNS() external view {
        for (uint16 i = 0; i < testIterations; i++) {

            uint256[] memory xp = allInputs[i].xp;
            uint256 tokenIndex = i % 3;
            uint256 d = allInputs[i].d;
            getYDNewtonsMethod(100, tokenIndex, xp, d);
        }
    }

    function gasTestQNM() external view {
        for (uint16 i = 0; i < testIterations; i++) {

            uint256[] memory xp = allInputs[i].xp;
            uint256 tokenIndex = i % 3;
            uint256 d = allInputs[i].d;
            getYDQuasiNewtonsMethod(100, tokenIndex, xp, d);
        }
    }



    function getBrM() external view {
        for (uint16 i = 0; i < testIterations; i++) {

            uint256[] memory xp = allInputs[i].xp;
            uint256 tokenIndex = i % 3;
            uint256 d = allInputs[i].d;
            getYDBroydenMethod(100, tokenIndex, xp, d);
        }
    }



}


/**
 * @dev Wrappers over Solidity's arithmetic operations. @OZ
 */
library SlightlySafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }

    /**
     * @notice Compares a and b and returns true if the difference between a and b
     *         is less than 1 or equal to each other.
     * @param a uint256 to compare with
     * @param b uint256 to compare with
     * @return True if the difference between a and b is less than 1 or equal,
     *         otherwise return false
     */
    function within1(uint256 a, uint256 b) internal pure returns (bool) {
        return (difference(a, b) <= 1);
    }

    /**
     * @notice Calculates absolute difference between a and b
     * @param a uint256 to compare with
     * @param b uint256 to compare with
     * @return Difference between a and b
     */
    function difference(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a - b;
        }
        return b - a;
    }
}
