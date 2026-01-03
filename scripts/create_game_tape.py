#!/usr/bin/env python3
"""Create a TU56 DECtape image with place names for a game."""

import struct
import sys

# TC08 constants
WORDS_PER_BLOCK = 129
DATA_WORDS_PER_BLOCK = 128
BLOCKS = 0o100  # 64 decimal blocks

# Place names (64 interesting locations)
PLACES = [
    "The Ancient Harbor",
    "Misty Moorlands",
    "Crystal Caverns",
    "Abandoned Observatory",
    "Whispering Woods",
    "Forgotten Temple",
    "Floating Islands",
    "Underground Lake",
    "Storm Peak Summit",
    "Desert Oasis",
    "Frozen Tundra",
    "Volcanic Forge",
    "Sunken City Ruins",
    "Enchanted Garden",
    "Shadow Valley",
    "Celestial Tower",
    "Deep Forest Glade",
    "Rocky Cliffs",
    "Merchant's Bazaar",
    "Hidden Sanctuary",
    "The Great Library",
    "Moonlit Beach",
    "Mountain Pass",
    "Old Mill",
    "Dragon's Lair",
    "Sacred Grove",
    "Windswept Plains",
    "Coral Reef",
    "Ice Palace",
    "Ruins of Atlantis",
    "Mystic Falls",
    "Bone Yard",
    "Golden Fields",
    "Dark Abyss",
    "Sky Bridge",
    "Emerald Mines",
    "Ghost Town",
    "Serpent's Nest",
    "Lighthouse Point",
    "Canyon Echo",
    "Wizard's Tower",
    "Fishing Village",
    "Jungle Canopy",
    "Stone Circle",
    "Pirate Cove",
    "Silver Lake",
    "Thunder Mountain",
    "Silk Road Outpost",
    "Swamp of Sorrows",
    "Paradise Valley",
    "Fortress Ruins",
    "Starlight Plateau",
    "Burning Sands",
    "River Crossing",
    "Cloud City",
    "Haunted Mansion",
    "Pearl Lagoon",
    "Amber Forest",
    "The Crossroads",
    "Sapphire Grotto",
    "Eternal Spring",
    "Ravens Nest",
    "The Lost Garden",
    "Iron Gate Keep",
]

def string_to_words(text):
    """Convert ASCII string to 16-bit words (Nova format: high byte first, low byte second)."""
    # Pad to even length
    if len(text) % 2 == 1:
        text += '\0'
    
    words = []
    for i in range(0, len(text), 2):
        # First char goes in high byte, second char in low byte
        word = (ord(text[i]) << 8) | ord(text[i + 1])
        words.append(word)
    
    # Add terminating zero if not already present
    if not words or words[-1] != 0:
        words.append(0)
    
    return words

def create_tape_image(filename):
    """Create a TU56 tape image with place names."""
    with open(filename, 'wb') as f:
        for block_num in range(BLOCKS):
            # Get place name for this block
            place_name = PLACES[block_num] if block_num < len(PLACES) else f"Location {block_num}"
            
            # Convert to words
            name_words = string_to_words(place_name)
            
            # Ensure we don't exceed 64 words
            if len(name_words) > 64:
                name_words = name_words[:64]
            
            # Pad to 128 data words
            block_data = name_words + [0] * (DATA_WORDS_PER_BLOCK - len(name_words))
            
            # Write 128 data words (BinaryReader reads little-endian)
            for word in block_data[:DATA_WORDS_PER_BLOCK]:
                f.write(struct.pack('<H', word))  # Little-endian uint16
            
            # Write the 129th word (block number/checksum - set to 0)
            f.write(struct.pack('<H', 0))
    
    print(f"Created {filename} with {BLOCKS} blocks ({BLOCKS * WORDS_PER_BLOCK * 2} bytes)")
    print(f"First 10 locations:")
    for i in range(min(10, len(PLACES))):
        print(f"  Block {i:03o} (dec {i:2d}): {PLACES[i]}")

if __name__ == '__main__':
    output_file = sys.argv[1] if len(sys.argv) > 1 else 'game.tu56'
    create_tape_image(output_file)
